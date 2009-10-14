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

begin
  require 'jeweler'
  $LOAD_PATH.unshift 'lib'
  require 'resque/version'

  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "resque"
    gemspec.summary = ""
    gemspec.description = ""
    gemspec.email = "chris@ozmm.org"
    gemspec.homepage = "http://github.com/defunkt/resque"
    gemspec.authors = ["Chris Wanstrath"]
    gemspec.version = Resque::Version + ".#{Time.to_i}"
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
end
