# encoding: utf-8
require 'date'
require "logstash/namespace"
require 'logstash/outputs/base'
require 'java'
require 'logstash-output-adls_jars.rb'

# ==== Usage
# This is an example of Logstash config:
#
# [source,ruby]
# ----------------------------------
# input {
#   ...
# }
# filter {
#   ...
# }
# output {
#   adls {
#     adls_fqdn => "XXXXXXXXXXX.azuredatalakestore.net"                                         # (required)
#     adls_token_endpoint => "https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token"        # (required)
#     adls_client_id => "00000000-0000-0000-0000-000000000000"                                  # (required)
#     adls_client_key => "XXXXXXXXXXXXXXXXXXXXXX"                                               # (required)
#     path => "/logstash/%{+YYYY}/%{+MM}/%{+dd}/logstash-%{+HH}-%{[@metadata][cid]}.log"        # (required)
#     test_path => "testfile"                                                                   # (optional, default "testfile")
#     line_separator => "\n"                                                                    # (optional, default: "\n")
#     created_files_permission => 755                                                           # (optional, default: 755)
#     adls_token_expire_security_margin => 300                                                  # (optional, default: 300)
#     single_file_per_thread = > true                                                           # (optional, default: true)
#     retry_interval => 0.5                                                                     # (optional, default: 0.5)
#     max_retry_interval => 10                                                                  # (optional, default: 10)
#     retry_times => 3                                                                          # (optional, default: 3)
#     exit_if_retries_exceeded => false                                                         # (optional, default: false)
#     codec => "json"                                                                           # (optional, default: default codec defined by Logstash)
#   }
# }
# ----------------------------------
class LogStash::Outputs::ADLS < LogStash::Outputs::Base

  config_name "adls"

  concurrency :shared

  # The Azure DLS FQDN
  config :adls_fqdn, :validate => :string, :required => true

  # The Azure Oauth Endpoint
  config :adls_token_endpoint, :validate => :string, :required => true

  # The Azure DLS ClientID
  config :adls_client_id, :validate => :string, :required => true

  # The  The Azure DLS ClientKey
  config :adls_client_key, :validate => :string, :required => true

  # The path to the file to write to. Event fields can be used here,
  # as well as date fields in the joda time format, e.g.:
  # `/user/logstash/dt=%{+YYYY-MM-dd}/%{@source_host}-%{+HH}.log`
  config :path, :validate => :string, :required => true

  # The path used for testing permissions in the datalake
  config :test_path, :validate => :string, :default => "testfile"

  # Line separator for events written.
  config :line_separator, :validate => :string, :default => "\n"

  # File permission for files created
  config :created_files_permission, :validate => :number, :default => 755

  # The security margin that shoud be subtracted to the token's expire value.
  config :adls_token_expire_security_margin, :validate => :number, :default => 300
  
  # Avoid appending to same file in multiple threads.
  # This solves some problems with multiple logstash output threads and locked file leases in webhdfs.
  # If this option is set to true, %{[@metadata][cid]} needs to be used in path config settting.
  config :single_file_per_thread, :validate => :boolean, :default => true

  # How long(in seconds) should we wait between retries in case of an error. This value is a coefficient 
  # and not an absolute value. The wait time is "retry_interval*tries_counter". So, if retry_interval is 1 
  # on the first retry, the wait time will be 1, on the second try will be 2, and so on.
  config :retry_interval, :validate => :number, :default => 1

  # Max Retry Interval. The actual wait time (in seconds) will be min(retry_interval*tries_counter", max_retry_interval).
  config :max_retry_interval, :validate => :number, :default => 10

  # How many times should we retry. If retry_times is exceeded, an error will be logged and the event will be discarded. (Set to -1 for unlimited retries)
  config :retry_times, :validate => :number, :default => 3

  # If enabled, Logstash will exit if retries are exceeded to avoid loosing events.
  config :exit_if_retries_exceeded, :validate => :boolean, :default => false

  attr_accessor :client
  attr_accessor :azureOauthTokenRefreshDate
  attr_accessor :timerTaskClass
  attr_accessor :timer
  
  public

    def register()

      begin
        @client = prepare_client(@adls_fqdn, @adls_client_id, @adls_token_endpoint, @adls_client_key,  @test_path)
      rescue => e
        logger.error("Cannot Login in ADLS. Aborting.... Exception: #{e.message}; Trace:#{e.backtrace.join("\n\t")}")
        exit 1
      end

      # Make sure @path contains %{[@metadata][thread_id]} format value
      if @single_file_per_thread and !@path.include? "%{[@metadata][cid]}"
        @logger.error("Please set %{[@metadata][cid]} format value in @path to avoid file locks in ADLS.")
        raise LogStash::ConfigurationError
      end

      @codec.on_event do |event, encoded_event|
        encoded_event
      end

      @timerTaskClass = Class.new java.util.TimerTask do
        def setContext(parent)
          @parent = parent
        end
        def run
          begin
            @parent.client = @parent.prepare_client(@parent.adls_fqdn, @parent.adls_client_id, @parent.adls_token_endpoint, @parent.adls_client_key, @parent.test_path)
          rescue => e
            sleepTime = [@parent.retry_interval, @parent.max_retry_interval].min
            @parent.logger.error("ADLS Refresh OAuth Token Failed! Retrying in #{sleepTime.to_s} seconds... Exception: #{e.message}; Trace:#{e.backtrace.join("\n\t")}")         
            sleep(sleepTime)
          end
          timerTask = @parent.timerTaskClass.new
          timerTask.setContext(@parent)
          @parent.timer.schedule(timerTask, @parent.azureOauthTokenRefreshDate) # Rearm timer
        end  
      end  

      timerTask = @timerTaskClass.new
      timerTask.setContext(self)

      @timer = java.util.Timer.new
      @timer.schedule(timerTask, @azureOauthTokenRefreshDate)

      @randomValuePerInstance = rand(10..10000) # To make sure different instances in different machines don't generate the same threadId.
  end

  def close
    @logger.info("Logstash ADLS output plugin is shutting down...")
  end

  def prepare_client(accountFQDN, clientId, authTokenEndpoint, clientKey, testPath)
    azureToken = com.microsoft.azure.datalake.store.oauth2.AzureADAuthenticator.getTokenUsingClientCreds(authTokenEndpoint, clientId, clientKey)

    calendar = java.util.Calendar.getInstance()
    calendar.setTime(azureToken.expiry)
    calendar.set(java.util.Calendar::SECOND,(calendar.get(java.util.Calendar::SECOND)-@adls_token_expire_security_margin))
    @azureOauthTokenRefreshDate = calendar.getTime()

    @logger.info("Got ADLS OAuth Token with expire date #{azureToken.expiry.to_s}. Token will be refreshed at #{@azureOauthTokenRefreshDate.to_s}")
    
    client = com.microsoft.azure.datalake.store.ADLStoreClient.createClient(accountFQDN, azureToken)
    options = com.microsoft.azure.datalake.store.ADLStoreOptions.new()
    options.setUserAgentSuffix("Logstash-ADLS-Output-Plugin")
    client.setOptions(options)
    client.checkExists(testPath) # Test the Client to make sure it works. The return value is irrelevant. 
    client
  end

  def multi_receive(events)
    return if not events

    timeElapsed = Time.now

    output_files = Hash.new { |hash, key| hash[key] = "" }
    events.collect do |event|

      if @single_file_per_thread
        event.set("[@metadata][cid]", "#{@randomValuePerInstance.to_s}#{Thread.current.object_id.to_s}")
      end

      path = event.sprintf(@path)
      event_as_string = @codec.encode(event)
      event_as_string +=  @line_separator unless event_as_string.end_with?  @line_separator
      output_files[path] << event_as_string
    end
  
    output_files.each do |path, output|
      # Retry max_retry times. This can solve problems like leases being hold by another process.
      write_tries = 0
      begin
        write_data(path, output)
      rescue Exception => e
        if (write_tries < @retry_times) or (@retry_times == -1)
          sleepTime = [@retry_interval * write_tries, @max_retry_interval].min
          @logger.warn("ADLS write caused an exception: #{e.message}. Maybe you should increase retry_interval or reduce number of workers. Attempt: #{write_tries.to_s}. Retrying in #{sleepTime.to_s} seconds...")
          sleep(sleepTime)
          write_tries += 1
          retry
        else
          if e.instance_of? com.microsoft.azure.datalake.store.ADLException
            @logger.error("Max write retries reached. Events discarded! ADLS_RemoteMessage: #{e.remoteExceptionMessage}; Exception: #{e.message};  ADLS_Path: #{path}; StackTrace:#{e.backtrace.join("\n\t")}")
          else
            @logger.error("Max write retries reached. Events discarded! Exception: #{e.message}; StackTrace:#{e.backtrace.join("\n\t")}")
          end
          if @exit_if_retries_exceeded
            exit 1
          end
        end
      end 
    end
    @logger.debug("#{events.length.to_s} events written on ADLS in #{Time.now-timeElapsed} seconds.")

  end

  def write_data(path, data)
    begin
      @logger.info("Trying to write at #{path}")
      adlsClient = @client
      
      # Try to append to already existing file, which will work most of the times.
      stream = adlsClient.getAppendStream(path)
      outStream = java.io.PrintStream.new(stream)
      outStream.print(data)
      outStream.close()
      stream.close()

    # File does not exist, so create it.
    rescue com.microsoft.azure.datalake.store.ADLException => e
      if e.httpResponseCode == 404
        createStream = adlsClient.createFile(path, com.microsoft.azure.datalake.store.IfExists::OVERWRITE, @created_files_permission.to_s, true)
        outStream = java.io.PrintStream.new(createStream)
        outStream.print(data)
        outStream.close()
        createStream.close()
        @logger.debug("File #{path} created.")
      else
         raise e  
      end           
    end
    #@logger.info("Data written to ADLS: #{data}")

  end
        
end