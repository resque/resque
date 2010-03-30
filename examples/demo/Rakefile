$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'
require 'resque/tasks'
require 'job'

desc "Start the demo using `rackup`"
task :start do 
  exec "rackup config.ru"
end
