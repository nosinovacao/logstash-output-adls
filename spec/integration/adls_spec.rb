# encoding: utf-8
require 'logstash/devutils/rspec/spec_helper'
require 'logstash/outputs/adls'
require 'json'
require 'java'

describe LogStash::Outputs::ADLS, :integration => true do

  let(:adls_fqdn) { 'XXXXXXXXXXX.azuredatalakestore.net' }
  let(:adls_token_endpoint) { 'https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token' }
  let(:adls_client_id) { '00000000-0000-0000-0000-000000000000' }
  let(:adls_client_key) { 'XXXXXXXXXXXXXXXXXXXXXX' }
  let(:path) { '/test.log' }

  let(:config) { { 'adls_fqdn' =>adls_fqdn, 'adls_token_endpoint' => adls_token_endpoint, 'adls_client_id' => adls_client_id, 'adls_client_key' => adls_client_key, 'path' => path, "single_file_per_thread" => false } }

  subject(:plugin) { LogStash::Plugin.lookup("output", "adls").new(config) }

  let(:event) { LogStash::Event.new('message' => 'Hello world!', 'source' => 'out of the blue',
                                    'type' => 'generator', 'host' => 'localhost' ) }

  describe "register and close" do

    it 'should register with default values' do
      expect { subject.register }.to_not raise_error
    end

  end

  describe '#write' do

    let(:AdlsClient) { nil }

    after(:each) do
      subject.close
      #deltefile
    end

    describe "writing plain files" do

      before(:each) do
        subject.register
        AdlsClient = subject.client
        subject.receive(event)
      end

      it 'should use the correct filename pattern' do
        expect { AdlsClient.checkExists(path) }.to eq(true)
      end

      context "using the line codec without format" do

        it 'should match the event data' do

          expected = expect do
            stream = AdlsClient.getReadStream(path)
            s = java.util.Scanner(stream).new.useDelimiter("\\A")
            result = s.hasNext() ? s.next() : ""
            result
          end
          expected.to eq(event.to_s)
        end

      end

      #context "using the json codec" do

        #let(:config) { { 'host' => host, 'user' => user, 'flush_size' => 10, 'path' => test_file, 'compression' => 'none', 'codec' => 'json' } }

        #it 'should match the event data' do
          #expect(webhdfs_client.read(hdfs_file_name).strip()).to eq(event.to_json)
        #end

      #end

    end

  end
end