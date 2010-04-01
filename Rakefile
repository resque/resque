#
# Setup
#

load 'tasks/redis.rake'
require 'rake/testtask'

$LOAD_PATH.unshift 'lib'
require 'resque/tasks'

def command?(command)
  system("type #{command} > /dev/null")
end


#
# Tests
#

task :default => :test

desc "Run the test suite"
task :test do
  rg = command?(:rg)
  Dir['test/**/*_test.rb'].each do |f|
    rg ? sh("rg #{f}") : ruby(f)
  end
end

if command? :kicker
  desc "Launch Kicker (like autotest)"
  task :kicker do
    puts "Kicking... (ctrl+c to cancel)"
    exec "kicker -e rake test lib examples"
  end
end


#
# Gem
#

task :install => [ 'redis:install', 'dtach:install' ]

desc "Build a gem"
task :gem => [ :test, :gemspec, :build ]

begin
  require 'jeweler'
  require 'resque/version'

  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "resque"
    gemspec.summary = "Resque is a Redis-backed queueing system."
    gemspec.email = "chris@ozmm.org"
    gemspec.homepage = "http://github.com/defunkt/resque"
    gemspec.authors = ["Chris Wanstrath"]
    gemspec.version = Resque::Version

    gemspec.add_dependency "redis"
    gemspec.add_dependency "redis-namespace"
    gemspec.add_dependency "vegas", ">=0.1.2"
    gemspec.add_dependency "sinatra", ">=0.9.2"
    gemspec.add_development_dependency "jeweler"

    gemspec.description = <<description
    Resque is a Redis-backed Ruby library for creating background jobs,
    placing those jobs on multiple queues, and processing them later.

    Background jobs can be any Ruby class or module that responds to
    perform. Your existing classes can easily be converted to background
    jobs or you can create new classes specifically to do work. Or, you
    can do both.

    Resque is heavily inspired by DelayedJob (which rocks) and is
    comprised of three parts:

    * A Ruby library for creating, querying, and processing jobs
    * A Rake task for starting a worker which processes jobs
    * A Sinatra app for monitoring queues, jobs, and workers.
description
  end
rescue LoadError
  puts "Jeweler not available. Install it with: "
  puts "gem install jeweler"
end


#
# Documentation
#

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
end


#
# Publishing
#

desc "Push a new version to Gemcutter"
task :publish => [ :test, :gemspec, :build ] do
  system "git tag v#{Resque::Version}"
  system "git push origin v#{Resque::Version}"
  system "git push origin master"
  system "gem push pkg/resque-#{Resque::Version}.gem"
  system "git clean -fd"
  exec "rake pages"
end
