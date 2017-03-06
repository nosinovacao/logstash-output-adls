# encoding: utf-8
Gem::Specification.new do |s|

  s.name            = 'logstash-output-adls'
  s.version         = '1.1.3'
  s.licenses        = ['Apache-2.0']
  s.summary         = "Plugin to write events to Azure DataLakeStore"
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors         = ["NOS Inovacao"]
  s.email           = 'nosi.metadata@nos.pt'
  s.homepage        = "http://www.nos.pt"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md', 'Gemfile','LICENSE','NOTICE.TXT']

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "output" }

  s.requirements << "jar 'com.microsoft.azure:azure-data-lake-store-sdk', '2.1.1'"
  s.requirements << "jar 'org.slf4j:slf4j-log4j12', '1.7.21'"

  s.add_development_dependency 'jar-dependencies', '~> 0.3.2'

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_development_dependency 'logstash-devutils'

  s.add_development_dependency 'logstash-codec-line'
  s.add_development_dependency 'logstash-codec-json'
  s.add_development_dependency 'logstash-codec-plain'


end
