require 'rake/testtask'
eval File.read('tasks/redis.rake')

$LOAD_PATH.unshift File.dirname(__FILE__) + '/lib'
require 'resque/tasks'

task :default => :test

Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end

task :install => [ 'redis:install', 'dtach:install' ]
