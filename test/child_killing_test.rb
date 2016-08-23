require 'test_helper'
require 'tmpdir'

describe "Resque::Worker" do

  class LongRunningJob
    @queue = :long_running_job

    def self.perform( sleep_time, rescue_time=nil )
      Resque.redis.client.reconnect # get its own connection
      Resque.redis.rpush( 'sigterm-test:start', Process.pid )
      sleep sleep_time
      Resque.redis.rpush( 'sigterm-test:result', 'Finished Normally' )
    rescue Resque::TermException => e
      Resque.redis.rpush( 'sigterm-test:result', %Q(Caught TermException: #{e.inspect}))
      sleep rescue_time
    ensure
      Resque.redis.rpush( 'sigterm-test:ensure_block_executed', 'exiting.' )
    end
  end

  def start_worker(rescue_time, term_child, term_timeout = 1)
    Resque.enqueue( LongRunningJob, 3, rescue_time )

    worker_pid = Kernel.fork do
      # reconnect since we just forked
      Resque.redis.client.reconnect

      worker = Resque::Worker.new(:long_running_job)
      worker.term_timeout = term_timeout
      worker.term_child = term_child

      suppress_warnings do
        worker.work(0)
      end
      exit!
    end

    # ensure the worker is started
    start_status = Resque.redis.blpop( 'sigterm-test:start', 5 )
    refute_nil start_status
    child_pid = start_status[1].to_i
    assert child_pid > 0, "worker child process not created"

    [worker_pid, child_pid]
  end

  def start_worker_and_kill_term(rescue_time, term_child, term_timeout = 1)
    worker_pid, child_pid = start_worker(rescue_time, term_child, term_timeout)

    Process.kill('TERM', worker_pid)
    Process.waitpid(worker_pid)
    result = Resque.redis.lpop('sigterm-test:result')
    [worker_pid, child_pid, result]
  end

  def assert_exception_caught(result)
    refute_nil result
    assert !result.start_with?('Finished Normally'), 'Job Finished normally.  (sleep parameter to LongRunningJob not long enough?)'
    assert result.start_with?("Caught TermException"), 'TermException exception not raised in child.'
  end

  def assert_child_not_running(child_pid)
    # ensure that the child pid is no longer running
    child_still_running = !(`ps -p #{child_pid.to_s} -o pid=`).empty?
    assert !child_still_running
  end

  if !defined?(RUBY_ENGINE) || RUBY_ENGINE != "jruby"
    it "old signal handling just kills off the child" do
      worker_pid, child_pid, result = start_worker_and_kill_term(0, false)
      assert_nil result
      assert_child_not_running child_pid
    end

    it "SIGTERM and cleanup occurs in allotted time" do
      worker_pid, child_pid, result = start_worker_and_kill_term(0, true)
      assert_exception_caught result
      assert_child_not_running child_pid

      # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
      post_cleanup_occurred = Resque.redis.lpop( 'sigterm-test:ensure_block_executed' )
      assert post_cleanup_occurred, 'post cleanup did not occur. SIGKILL sent too early?'
    end

    it "SIGTERM and cleanup does not occur in allotted time" do
      worker_pid, child_pid, result = start_worker_and_kill_term(5, true, 0.1)
      assert_exception_caught result
      assert_child_not_running child_pid

      # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
      post_cleanup_occurred = Resque.redis.lpop( 'sigterm-test:ensure_block_executed' )
      assert !post_cleanup_occurred, 'post cleanup occurred. SIGKILL sent too late?'
    end
  end

  it "exits with Resque::TermException when using TERM_CHILD and not forking" do
    old_job_per_fork = ENV['FORK_PER_JOB']
    begin
      ENV['FORK_PER_JOB'] = 'false'
      worker_pid, child_pid, result = start_worker_and_kill_term(0, true)
      assert_equal worker_pid, child_pid, "child_pid should equal worker_pid, since we are not forking"
      assert Resque.redis.lpop( 'sigterm-test:ensure_block_executed' ), 'post cleanup did not occur. SIGKILL sent too early?'
    ensure
      ENV['FORK_PER_JOB'] = old_job_per_fork
    end
  end

  it 'sending signal to a forked child should not make a effect to its parent' do
    worker_pid, child_pid = start_worker(0, false)

    Process.kill('TERM', child_pid)
    10.times do
      assert_nil Process.waitpid(worker_pid, Process::WNOHANG) # should not die
      sleep 0.1
    end

    Process.kill('TERM', worker_pid)
    Process.waitpid(worker_pid)
    result = Resque.redis.lpop('sigterm-test:result')
  end

end
