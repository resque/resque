require 'rake/testtask'
eval File.read('tasks/redis.rake')

$LOAD_PATH.unshift File.dirname(__FILE__) + '/lib'
require 'resque/tasks'

task :default => :test

task :test do
  # Don't use the rake/testtask because it loads a new
  # Ruby interpreter - we want to run tests with the current
  # `rake` so our library manager still works
  Dir['test/*_test.rb'].each do |f|
    require f
  end
end

task :install => [ 'redis:install', 'dtach:install' ]

desc "Build a gem"
task :gem => [ :gemspec, :build ]

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
    gemspec.version = Resque::Version + ".#{Time.now.to_i}"
  end
rescue LoadError
  puts "Jeweler not available. Install it with: "
  puts "gem install jeweler"
end

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
end
