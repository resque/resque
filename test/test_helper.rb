require 'rubygems'
require 'timeout'
require 'bundler/setup'
require 'redis/namespace'
require 'minitest/autorun'

$dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift $dir + '/../lib'
require 'resque'
$TESTING = true

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

MiniTest::Unit.after_tests do
  processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
  pids = processes.map { |process| process.split(" ")[0] }
  puts "Killing test redis server..."
  pids.each { |pid| Process.kill("TERM", pid.to_i) }
  system("rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb")
end

if ENV.key? 'RESQUE_DISTRIBUTED'
  require 'redis/distributed'
  puts "Starting redis for testing at localhost:9736 and localhost:9737..."
  `redis-server #{$dir}/redis-test.conf`
  `redis-server #{$dir}/redis-test-cluster.conf`
  r = Redis::Distributed.new(['redis://localhost:9736', 'redis://localhost:9737'])
  Resque.redis = Redis::Namespace.new :resque, :redis => r
else
  puts "Starting redis for testing at localhost:9736..."
  `redis-server #{$dir}/redis-test.conf`
  Resque.redis = 'localhost:9736'
end

class DummyLogger
  attr_reader :messages

  def initialize
    @messages = []
  end

  def info(message); @messages << message; end
  alias_method :debug, :info
  alias_method :warn,  :info
  alias_method :error, :info
  alias_method :fatal, :info
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

class NestedJob
  @queue = :nested
  def self.perform
    Resque.enqueue(SomeIvarJob, 20, '/tmp')
  end
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

class JobWithNoQueue
  def self.perform
    "I don't have a queue."
  end
end

def with_failure_backend(failure_backend, &block)
  previous_backend = Resque::Failure.backend
  Resque::Failure.backend = failure_backend
  yield block
ensure
  Resque::Failure.backend = previous_backend
end

require 'time'

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

# Log to log/test.log
def reset_logger
  $test_logger ||= Logger.new(File.open(File.expand_path("../../log/test.log", __FILE__), "w"))
  Resque.logger = $test_logger
end

reset_logger
