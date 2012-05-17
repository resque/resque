require 'rubygems'

dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift dir + '/../lib'
$TESTING = true

require 'minitest/unit'
require 'minitest/spec'
require 'test/unit'
require 'mocha'

require 'redis/namespace'
require 'resque'

#
# make sure we can run redis
#

if !system("which redis-server")
  puts '', "** can't find `redis-server` in your path"
  puts "** try running `sudo rake install`"
  abort ''
end


#
# start our own redis when the tests start,
# kill it when they end
#

at_exit do
  next if $!

  if defined?(MiniTest)
    exit_code = MiniTest::Unit.new.run(ARGV)
  else
    exit_code = Test::Unit::AutoRunner.run
  end

  processes = `ps -A -o pid,command | grep [r]edis-test`.split("\n")
  pids = processes.map { |process| process.split(" ")[0] }
  puts "Killing test redis server..."
  `rm -f #{dir}/dump.rdb #{dir}/dump-cluster.rdb`
  pids.each { |pid| Process.kill("KILL", pid.to_i) }
  exit exit_code
end

if ENV.key? 'RESQUE_DISTRIBUTED'
  require 'redis/distributed'
  puts "Starting redis for testing at localhost:9736 and localhost:9737..."
  `redis-server #{dir}/redis-test.conf`
  `redis-server #{dir}/redis-test-cluster.conf`
  r = Redis::Distributed.new(['redis://localhost:9736', 'redis://localhost:9737'])
  Resque.redis = Redis::Namespace.new :resque, :redis => r
else
  puts "Starting redis for testing at localhost:9736..."
  `redis-server #{dir}/redis-test.conf`
  Resque.redis = 'localhost:9736'
end


##
# Helper to perform job classes
#
module PerformJob
  def perform_job(klass, *args)
    resque_job = Resque::Job.new(:testqueue, 'class' => klass, 'args' => args)
    resque_job.perform
  end
end

#
# fixture classes
#

class SomeJob
  def self.perform(repo_id, path)
  end
end

class SomeIvarJob < SomeJob
  @queue = :ivar
end

class SomeMethodJob < SomeJob
  def self.queue
    :method
  end
end

class BadJob
  def self.perform
    raise "Bad job!"
  end
end

class GoodJob
  def self.perform(name)
    "Good job, #{name}"
  end
end

class BadJobWithSyntaxError
  def self.perform
    raise SyntaxError, "Extra Bad job!"
  end
end

class BadFailureBackend < Resque::Failure::Base
  def save
    raise Exception.new("Failure backend error")
  end
end

def with_failure_backend(failure_backend, &block)
  previous_backend = Resque::Failure.backend
  Resque::Failure.backend = failure_backend
  yield block
ensure
  Resque::Failure.backend = previous_backend
end

class Time
  # Thanks, Timecop
  class << self
    attr_accessor :fake_time

    alias_method :now_without_mock_time, :now

    def now
      fake_time || now_without_mock_time
    end
  end

  self.fake_time = nil
end
