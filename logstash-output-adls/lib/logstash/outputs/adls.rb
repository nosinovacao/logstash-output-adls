# encoding: utf-8
require 'date'
require "logstash/namespace"
require "logstash/outputs/base"
require 'com/microsoft/azure/azure-data-lake-store-sdk/2.1.1/azure-data-lake-store-sdk-2.1.1.jar'

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
#     adls_fqdn => "XXXXXXXXXXX.azuredatalakestore.net"                                       # (required)
#     adls_token_endpoint => "https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token"      # (required)
#     adls_client_id => "00000000-0000-0000-0000-000000000000"                                # (required)
#     adls_client_key => "XXXXXXXXXXXXXXXXXXXXXX"                                             # (required)
#     path => "/logstash/%{+YYYY-MM-dd}/logstash-%{+HH}-%{[@metadata][thread_id]}.log"        # (required)
#     created_files_permission => 755                                                         # (optional, default: 755)
#     adls_token_expire_security_margin => 300                                                # (optional, default: 300)
#     single_file_per_thread = > true                                                         # (optional, default: true)
#     retry_interval => 0.5                                                                   # (optional, default: 0.5)
#     retry_times => 3                                                                        # (optional, default: 3)
#   }
# }
# ----------------------------------
class LogStash::Outputs::AzureDLS < LogStash::Outputs::Base

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

  # File permission for files created
  config :created_files_permission, :validate => :number, :default => 755

  # The security margin that shoud be subtracted to the token's expire value.
  config :adls_token_expire_security_margin, :validate => :number, :default => 300
  
  # Avoid appending to same file in multiple threads.
  # This solves some problems with multiple logstash output threads and locked file leases in webhdfs.
  # If this option is set to true, %{[@metadata][thread_id]} needs to be used in path config settting.
  config :single_file_per_thread, :validate => :boolean, :default => true

  # How long should we wait between retries in case of an error.
  config :retry_interval, :validate => :number, :default => 0.5

  # How many times should we retry. If retry_times is exceeded, an error will be logged and the event will be discarded.
  config :retry_times, :validate => :number, :default => 3


  attr_accessor :client
  attr_accessor :azureOauthTokenRefreshDate
  attr_accessor :timerTaskClass
  attr_accessor :timer
  

  public

    def register()

      @client = prepare_client(@adls_fqdn, @adls_client_id, @adls_token_endpoint, @adls_client_key)

      # Make sure @path contains %{[@metadata][thread_id]} format value
      if @single_file_per_thread and !@path.include? "%{[@metadata][thread_id]}"
        @logger.error("Please set %{[@metadata][thread_id]} format value in @path to avoid file locks in ADL.")
        raise LogStash::ConfigurationError
      end

      @timerTaskClass = Class.new java.util.TimerTask do
        def setContext(parent)
          @parent = parent
        end
        def run
          @parent.client = @parent.prepare_client(@parent.adls_fqdn, @parent.adls_client_id, @parent.adls_token_endpoint, @parent.adls_client_key)
          timerTask = @parent.timerTaskClass.new
          timerTask.setContext(@parent)
          @parent.timer.schedule(timerTask, @parent.azureOauthTokenRefreshDate) # Rearm timer
        end  
      end  

      timerTask = @timerTaskClass.new
      timerTask.setContext(self)

      @timer = java.util.Timer.new
      @timer.schedule(timerTask, @azureOauthTokenRefreshDate)

    end


  def prepare_client(accountFQDN, clientId, authTokenEndpoint, clientKey)
    begin
      azureToken = com.microsoft.azure.datalake.store.oauth2.AzureADAuthenticator.getTokenUsingClientCreds(authTokenEndpoint, clientId, clientKey)

      calendar = java.util.Calendar.getInstance()
      calendar.setTime(azureToken.expiry)
      calendar.set(java.util.Calendar::SECOND,(calendar.get(java.util.Calendar::SECOND)-@adls_token_expire_security_margin))
      @azureOauthTokenRefreshDate = calendar.getTime()

      @logger.info("Azure ADL Oauth Token:" + azureToken.accessToken)
      @logger.info("Azure ADL Oauth Token expires at " + azureToken.expiry.to_s + " and will be refreshed at " + @azureOauthTokenRefreshDate.to_s)
      
      client = com.microsoft.azure.datalake.store.ADLStoreClient.createClient(accountFQDN, azureToken)
      options = com.microsoft.azure.datalake.store.ADLStoreOptions.new()
      options.setUserAgentSuffix("Logstash-ADLS-Output-Plugin")
      client.setOptions(options)
    rescue => e
      logger.error("AzureAuth Exception: #{e.message}; Trace:#{e.backtrace.join("\n\t")}")
    end
    client
  end

  def multi_receive(events)
    return if not events

    newline = "\n"
    output_files = Hash.new { |hash, key| hash[key] = "" }
    events.collect do |event|

      if @single_file_per_thread
        event.set("[@metadata][thread_id]", Thread.current.object_id.to_s)
      end

      path = event.sprintf(@path)
      event_as_string = event.to_s
      event_as_string += newline unless event_as_string.end_with? newline
      output_files[path] << event_as_string

      output_files.each do |path, output|

        # Retry max_retry times. This can solve problems like leases being hold by another process.
        write_tries = 0
        begin
          write_data(path, output)
        rescue Exception => e
          if write_tries < @retry_times
            @logger.warn("Azuredls write caused an exception: #{e.message}. Maybe you should increase retry_interval or reduce number of workers. Retrying...")
            sleep(@retry_interval * write_tries)
            write_tries += 1
            retry
          else
            if e.instance_of? com.microsoft.azure.datalake.store.ADLException
              @logger.error("Max write retries reached. Events will be discarded. AzureDLS_RemoteMessage: #{e.remoteExceptionMessage}; Exception: #{e.message};  StackTrace:#{e.backtrace.join("\n\t")}")
            else
              @logger.error("Max write retries reached. Events will be discarded. Exception: #{e.message}; StackTrace:#{e.backtrace.join("\n\t")}")
            end
          end
        end 
        @logger.info(events.length.to_s + " events written on Azure DataLake Store")

      end
    end

  end

  def write_data(path, data)
    begin
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
        @logger.info("File " + path + " created and batch written on Azure DataLake Store")
      else
         raise e  
      end           
    end
    #@logger.info("Data written to Azure DataLakeStore: "+ data)

  end
        
end