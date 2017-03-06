# encoding: utf-8
require 'logstash/devutils/rspec/spec_helper'
require 'logstash/outputs/adls'

describe 'outputs/adls' do

  let(:adls_fqdn) { 'XXXXXXXXXXX.azuredatalakestore.net' }
  let(:adls_token_endpoint) { 'https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token' }
  let(:adls_client_id) { '00000000-0000-0000-0000-000000000000' }
  let(:adls_client_key) { 'XXXXXXXXXXXXXXXXXXXXXX' }
  let(:path) { '/test.log' }

  let(:config) { { 'adls_fqdn' =>adls_fqdn, 'adls_token_endpoint' => adls_token_endpoint, 'adls_client_id' => adls_client_id, 'adls_client_key' => adls_client_key, 'path' => path } }

  subject(:plugin) { LogStash::Plugin.lookup("output", "adls").new(config) }

  describe '#initializing' do

    it 'should fail to register without %{[@metadata][cid]} in the path' do
      plugin = LogStash::Plugin.lookup("output", "adls")
      expect { plugin.new }.to raise_error(error=LogStash::ConfigurationError)
    end

    context "default values" do

      it 'should have default line_separator' do
        expect(subject.line_separator).to eq("\n")
      end

      it 'should have default created_files_permission' do
        expect(subject.created_files_permission).to eq(755)
      end
      it 'should have default adls_token_expire_security_margin' do
        expect(subject.adls_token_expire_security_margin).to eq(300)
      end

      it 'should have default single_file_per_thread' do
        expect(subject.single_file_per_thread).to eq(true)
      end

      it 'should have default retry_interval' do
        expect(subject.retry_interval).to eq(1)
      end

      it 'should have default max_retry_interval' do
        expect(subject.max_retry_interval).to eq(10)
      end

      it 'should have default retry_times' do
        expect(subject.retry_times).to eq(3)
      end

      it 'should have default exit_if_retries_exceeded' do
        expect(subject.exit_if_retries_exceeded).to eq(false)
      end

    end
  end
end
