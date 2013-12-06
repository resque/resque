require 'rubygems'
require 'timeout'
require 'bundler/setup'
require 'redis/namespace'
require 'minitest/autorun'

def as_long_as_it_mostly_works(&block)
  retry_count = 0
  timeout(10) do
    yield
  end
rescue => e
  retry_count += 1
  if retry_count > 4
    raise e
  else
    puts e.inspect
    puts e.backtrace.join("\n")
    retry
  end
end

$dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift $dir + '/../lib'
require 'resque'
$TEST_PID = Process.pid

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
  if Process.pid == $TEST_PID
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    system("rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb")
  end
end

require 'mock_redis'
puts "Using a mock Redis"
$reset_mock_redis = Proc.new do
  r = MockRedis.new :host => "localhost", :port => 9736, :db => 0
  $mock_redis = Redis::Namespace.new :resque, :redis => r
  Resque.redis = $mock_redis
end
$reset_mock_redis.call

if ENV.key? 'RESQUE_DISTRIBUTED'
  require 'redis/distributed'
  puts "Starting redis for testing at localhost:9736 and localhost:9737..."
  `redis-server #{$dir}/redis-test.conf`
  `redis-server #{$dir}/redis-test-cluster.conf`
  r = Redis::Distributed.new(['redis://localhost:9736', 'redis://localhost:9737'])
  $real_redis = Redis::Namespace.new :resque, :redis => r
else
  puts "Starting redis for testing at localhost:9736..."
  `redis-server #{$dir}/redis-test.conf`
  $real_redis = 'localhost:9736'
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


##
# Add helper methods to Kernel
#
module Kernel
  def silence_warnings
    with_warnings(nil) { yield }
  end unless Kernel.respond_to?(:silence_warnings)

  def with_warnings(flag)
    old_verbose, $VERBOSE = $VERBOSE, flag
    yield
  ensure
    $VERBOSE = old_verbose
  end unless Kernel.respond_to?(:with_warnings)

  def jruby?
    defined?(JRUBY_VERSION)
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

class InferredWorker < SomeJob; end
class InferredJob    < SomeJob; end
class JobNotAmI      < SomeJob; end

module Inferred; end
class Inferred::Job         < SomeJob; end

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

class AtExitJob
  def self.perform(filename)
    at_exit do
      File.open(filename, "w") {|file| file.puts "at_exit"}
    end
    "at_exit job"
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

require 'tempfile'
def reset_logger
  $test_logger ||= MonoLogger.new(Tempfile.new("resque.log"))
  Resque.logger = $test_logger
end

reset_logger

def stub_to_fork(worker, should_fork, &block)
  worker.options.stub(:fork_per_job, should_fork, &block)
end
