# Azure Data Lake Store Output Logstash Plugin

This is a Azure Data Laka Store Output Plugin for [Logstash](https://github.com/elastic/logstash).

This plugin uses the official [Microsoft Data Lake Store Java SDK](https://github.com/Azure/azure-data-lake-store-java) with their custom [AzureDataLakeFilesystem - ADL](https://docs.microsoft.com/en-us/azure/data-lake-store/data-lake-store-overview#what-is-azure-data-lake-store-file-system-adl) protocol, which Microsoft claims is more efficient than WebHDFS.

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Installing

TBD

### Manual installation on a already deployed Logstash:

You can install the plugin on a already deployed Logstash and avoid messing with the Logstash Gemfile. 
Please note that in this mode you can't alter the plugin source (logstash-output-adls/lib/logstash/outputs/adls.rb) without rebuilding the gem, which makes sense for a production deploy.

Note that you'll need an already built gem file from the previous step.

- Copy logstash-output-adls-x.x.x.gem to your remote Logstash.
- Install the package on your remote Logstash:

```sh
bin/logstash-plugin install /your/local/logstash-output-adls-x.x.x.gem
```

## Configuration

### Configuration example:

 ```
 input {
   ...
 }
 filter {
   ...
 }
 output {
   adls {
     adls_fqdn => "XXXXXXXXXXX.azuredatalakestore.net"                                        # (required)
     adls_token_endpoint => "https://login.microsoftonline.com/XXXXXXXXXX/oauth2/token"       # (required)
     adls_client_id => "00000000-0000-0000-0000-000000000000"                                 # (required)
     adls_client_key => "XXXXXXXXXXXXXXXXXXXXXX"                                              # (required)
     path => "/logstash/%{+YYYY}/%{+MM}/%{+dd}/logstash-%{+HH}-%{[@metadata][cid]}.log"       # (required)
     line_separator => "\n"                                                                   # (optional, default: "\n")
     created_files_permission => 755                                                          # (optional, default: 755)
     adls_token_expire_security_margin => 300                                                 # (optional, default: 300)
     single_file_per_thread => true                                                           # (optional, default: true)
     retry_interval => 0.5                                                                    # (optional, default: 0.5)
     max_retry_interval => 10                                                                 # (optional, default: 10)
     retry_times => 3                                                                         # (optional, default: 3)
     exit_if_retries_exceeded => false                                                        # (optional, default: false)
     codec => "json"                                                                          # (optional, default: default codec defined by Logstash)
   }
 }
```

### Configuration fields:

| Setting | Required | Default | Description |
| --- | --- | --- | --- |
| `adls_fqdn` | yes | | Azure DLS FQDN |
| `adls_token_endpoint` | yes | | Azure Oauth Endpoint |
| `adls_client_id` | yes | | Azure DLS ClientID |
| `adls_client_key` | yes | | Azure DLS ClientKey |
| `path` | yes | | The path to the file to write to. Event fields can be used here, as well as date fields in the joda time format, e.g.: `/logstash/%{+YYYY-MM-dd}/logstash-%{+HH}-%{[@metadata][cid]}.log` |
| `line_separator` | no | `\n` | Line separator for events written |
| `created_files_permission` | no | 755 | File permission for files created |
| `adls_token_expire_security_margin` | no | 300 | The security margin (in seconds) that shoud be subtracted to the token's expire value to calculate when the token shoud be renewed. (i.e. If the Oauth token expires in 1hour, it will be renewed in "1hour -adls_token_expire_security_margin " |
| `single_file_per_thread` | no | true | Avoid appending to same file in multiple threads. This solves some problems with multiple logstash output threads and locked file leases in ADLS. If this option is set to true, %{[@metadata][cid]} needs to be used in path config settting. %{[@metadata][cid]} (cid->concurrentId) is generated from a random value computed when the logstash instance starts plus a per thread id. This setting is used to deal with ADLS 0x83090a16 errors. (see Configuration notes) |
| `retry_interval` | no | 1 | How long(in seconds)  should we wait between retries in case of an error. This value is a coefficient and not an absolute value. The wait time is "retry_interval*tries_counter". So, if retry_interval is 1 on the first retry, the wait time will be 1, on the second try will be 2, and so on |
| `max_retry_interval` | no | 10 | Max Retry Interval. The actual wait time (in seconds) will be min(retry_interval*tries_counter", max_retry_interval) |
| `retry_times` | no | 3 | How many times should we retry. If retry_times is exceeded, an error will be logged and the event will be discarded. (Set to -1 for unlimited retries) |
| `exit_if_retries_exceeded` | no | false | If enabled, Logstash will exit if retries are exceeded to avoid loosing events |
| `codec` | no | Logstash default codec | The Codec that will be used to serialize the event.(ex: CSV, JSON, LINE, etc) If you do not define one, Logstash will use it's default. Please refer to Logstash documentation |


### Concurrency and batching:
This plugin relies only on Logstash concurrency/batching facilities and can configured by Logstash's own "pipeline.workers" and "pipeline.batch.size" settings. Also, the concurrency mode of this plugin is set to [shared](https://www.elastic.co/guide/en/logstash/current/_how_to_write_a_logstash_output_plugin.html#_see_what_your_plugin_looks_like_4) to maximize concurrency.

### Configuration notes:

- If **single_file_per_thread** is enabled (and it is by defaut) and you're using more than one working thread, you'll need to add **%{[@metadata][cid]}** to your file path. This concatenates a ConcurrentID value to your path to avoid remote concurrency problems in ADLS. Apparently, ADLS locks the file for writing.
- If you you still have errors in your log like "**APPEND failed with error 0x83090a16 (Internal server error.)**" you should lower your concurrency and/or batching settings to avoid these kind of errors. We try to mitigate the problem with a backoff and retry strategy (**retry_interval** and **retry_times** settings) but AFAIK, there's nothing this plugin can do to avoid that entirely, it's an ADLS problem. Maybe they should queue their writing requests internally instead of writing them directly to the FS to avoid file write locks???
- However, unless you have very high concurrency and/or a large batch size, these errors shouldn't be a problem.


## Build & Development

### Build
- To get started, you'll need JRuby with the Bundler and Rake gems installed.

- Install dependencies:
```sh
bundle install
```

- Install Java dependencies from Maven:
```sh
rake install_jars
```

- Build your plugin gem:

```sh
gem build logstash-output-adls.gemspec
```

### Run in a local Logstash for development purposes.

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```sh
gem "logstash-output-adls", :path => "/your/local/logstash-output-adls"
```

- Install plugin:
```sh
bin/logstash-plugin install --no-verify
```