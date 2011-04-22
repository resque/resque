# require 'resque/tasks'
# will give you the resque tasks

Dir["#{File.dirname(__FILE__)}/../../tasks/*.rake"].each { |ext| load ext }