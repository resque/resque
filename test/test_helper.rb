require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'
require 'redis/namespace'
require 'mocha/setup'
require 'tempfile'

$dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift $dir + '/../lib'
ENV['TERM_CHILD'] = "1"
require 'resque'
$TEST_PID=Process.pid

begin
  require 'leftright'
rescue LoadError
end


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
    processes = `ps -A -o pid,command | grep [r]edis-test`.split("\n")
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    system("rm -f #{$dir}/dump.rdb #{$dir}/dump-cluster.rdb")
  end
end

class GlobalSpecHooks < MiniTest::Spec
  def setup
    super
    reset_logger
    Resque.redis.redis.flushall
    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil
  end

  def teardown
    super
    Resque::Worker.kill_all_heartbeat_threads
  end

  register_spec_type(/.*/, self)
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
# Helper to make Minitest::Assertion exceptions work properly
# in the block given to Resque::Worker#work.
#
module AssertInWorkBlock
  # if a block is given, ensure that it is run, and that any assertion
  # failures that occur inside it propagate up to the test.
  def work(*args, &block)
    return super unless block_given?

    ex = catch(:exception_in_block) do
      block_called = nil
      retval = super(*args) do |*bargs|
        begin
          block_called = true
          block.call(*bargs)
        rescue MiniTest::Assertion => ex
          throw :exception_in_block, ex
        end
      end

      raise "assertion block not called!" unless block_called

      return retval
    end

    ex && raise(ex)
  end
end

#
# fixture classes
#

class SomeJob
  def self.perform(repo_id, path)
  end
end

class JsonObject
  def to_json(opts = {})
    val = Resque.redis.get("count")
    { "val" => val }.to_json
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

class BadJobWithOnFailureHookFail < BadJobWithSyntaxError
  def self.on_failure_fail_hook(*args)
    raise RuntimeError.new("This job is just so bad!")
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

# From minitest/unit
def capture_io
  require 'stringio'

  orig_stdout, orig_stderr         = $stdout, $stderr
  captured_stdout, captured_stderr = StringIO.new, StringIO.new
  $stdout, $stderr                 = captured_stdout, captured_stderr

  yield

  return captured_stdout.string, captured_stderr.string
ensure
  $stdout = orig_stdout
  $stderr = orig_stderr
end

def capture_io_with_pipe
  orig_stdout, orig_stderr = $stdout, $stderr
  stdout_rd, $stdout = IO.pipe
  stderr_rd, $stderr = IO.pipe

  yield

  $stdout.close
  $stderr.close
  return stdout_rd.read, stderr_rd.read
ensure
  $stdout = orig_stdout
  $stderr = orig_stderr
end

# Log to log/test.log
def reset_logger
  $test_logger ||= MonoLogger.new(File.open(File.expand_path("../../log/test.log", __FILE__), "w"))
  Resque.logger = $test_logger
end

def suppress_warnings
  old_verbose, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = old_verbose
end

def without_forking
  orig_fork_per_job = ENV['FORK_PER_JOB']
  begin
    ENV['FORK_PER_JOB'] = 'false'
    yield
  ensure
    ENV['FORK_PER_JOB'] = orig_fork_per_job
  end
end

def with_pidfile
  old_pidfile = ENV["PIDFILE"]
  begin
    file = Tempfile.new("pidfile")
    file.close
    ENV["PIDFILE"] = file.path
    yield
  ensure
    file.unlink if file
    ENV["PIDFILE"] = old_pidfile
  end
end

def with_fake_time(time)
  old_time = Time.fake_time
  Time.fake_time = time
  yield
ensure
  Time.fake_time = old_time
end

def with_background
  old_background = ENV["BACKGROUND"]
  begin
    ENV["BACKGROUND"] = "true"
    yield
  ensure
    ENV["BACKGROUND"] = old_background
  end
end
