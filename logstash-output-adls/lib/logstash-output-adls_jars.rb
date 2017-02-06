# this is a generated file, to avoid over-writing it just delete this comment
begin
  require 'jar_dependencies'
rescue LoadError
  require 'com/fasterxml/jackson/core/jackson-core/2.7.4/jackson-core-2.7.4.jar'
  require 'org/slf4j/slf4j-api/1.7.21/slf4j-api-1.7.21.jar'
  require 'org/slf4j/slf4j-log4j12/1.7.21/slf4j-log4j12-1.7.21.jar'
  require 'log4j/log4j/1.2.17/log4j-1.2.17.jar'
  require 'com/microsoft/azure/azure-data-lake-store-sdk/2.1.1/azure-data-lake-store-sdk-2.1.1.jar'
end

if defined? Jars
  require_jar( 'com.fasterxml.jackson.core', 'jackson-core', '2.7.4' )
  require_jar( 'org.slf4j', 'slf4j-api', '1.7.21' )
  require_jar( 'org.slf4j', 'slf4j-log4j12', '1.7.21' )
  require_jar( 'log4j', 'log4j', '1.2.17' )
  require_jar( 'com.microsoft.azure', 'azure-data-lake-store-sdk', '2.1.1' )
end
