# Azure Data Laka Store Output Logstash Plugin

This is a Azure Data Laka Store Output Logstash Plugin for [Logstash](https://github.com/elastic/logstash).

This plugin uses the official [Microsoft Data Lake Store Java SDK](https://github.com/Azure/azure-data-lake-store-java) with their custom ADL protocol.

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.



## Build & Install

### 1. Build
- To get started, you'll need JRuby with the Bundler and Rake gems installed.

- Install dependencies
```sh
bundle install
```

- Install Java dependencies from Maven
```sh
rake install_jars
```

- Build your plugin gem

```sh
gem build logstash-output-adls.gemspec
```

### 2. Run in an installed Logstash

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-output-adls", :path => "/your/local/logstash-output-adls"
```

- Install plugin
```sh
bin/logstash-plugin install --no-verify
```

### 3. Configuration

#### 3.1 Configuration example:

 ```input {
   ...
 }
 filter {
   ...
 }
 output {
   adls {
     adls_fqdn => "XXXXXXXXXXX.azuredatalakestore.net"                                        (required)
     adls_token_endpoint => "https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token"       (required)
     adls_client_id => "00000000-0000-0000-0000-000000000000"                                 (required)
     adls_client_key => "XXXXXXXXXXXXXXXXXXXXXX"                                              (required)
     path => "/logstash/%{+YYYY-MM-dd}/logstash-%{+HH}-%{[@metadata][thread_id]}.log"         (required)
     created_files_permission => 755                                                          (optional, default: 755)
     adls_token_expire_security_margin => 300                                                 (optional, default: 300)
     single_file_per_thread = > true                                                          (optional, default: true)
     retry_interval => 0.5                                                                    (optional, default: 0.5)
     retry_times => 3                                                                         (optional, default: 3)
   }
 }
```

#### 3.2 Configuration fields:

- **adls_fqdn** (required) -> Azure DLS FQDN.
- **adls_token_endpoint** (required) -> Azure Oauth Endpoint.
- **adls_client_id** (required) -> Azure DLS ClientID.
- **adls_client_key** (required) -> Azure DLS ClientKey.
- **path** (required) -> The path to the file to write to. Event fields can be used here,
 as well as date fields in the joda time format, e.g.:
 `/logstash/%{+YYYY-MM-dd}/logstash-%{+HH}-%{[@metadata][thread_id]}.log`.
- **created_files_permission** (optional, default: 755) -> File permission for files created.
- **adls_token_expire_security_margin** (optional, default: 300) -> The security margin that shoud be subtracted to the token's expire value to calculte when the token shoud be renewed.
- **single_file_per_thread** (optional, default: true) -> Avoid appending to same file in multiple threads. This solves some problems with multiple logstash output threads and locked file leases in AzureDLS. If this option is set to true, %{[@metadata][thread_id]} needs to be used in path config settting.
- **retry_interval** (optional, default: 0.5) -> How long should we wait between retries in case of an error.
- **retry_times** (optional, default: 3) -> How many times should we retry. If retry_times is exceeded, an error will be logged and the event will be discarded.