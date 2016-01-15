require 'test_helper'
require 'tmpdir'
require 'fixtures/long_running_job'

describe "Resque::Worker" do
  def start_worker(rescue_time, term_child)
    Resque.enqueue( LongRunningJob, 3, rescue_time )

    worker_pid = Kernel.fork do
      # reconnect since we just forked
      Resque.redis.client.reconnect

      worker = Resque::Worker.new(:long_running_job)
      worker.term_timeout = 1
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

    Process.kill('TERM', worker_pid)
    Process.waitpid(worker_pid)
    result = Resque.redis.blpop( 'sigterm-test:result', 5 )
    [worker_pid, child_pid, result]
  end

  def assert_exception_caught(result)
    refute_nil result
    assert !result[1].start_with?('Finished Normally'), 'Job Finished normally.  (sleep parameter to LongRunningJob not long enough?)'
    assert result[1].start_with?("Caught TermException"), 'TermException exception not raised in child.'
  end

  def assert_child_not_running(child_pid)
    # ensure that the child pid is no longer running
    child_still_running = !(`ps -p #{child_pid.to_s} -o pid=`).empty?
    assert !child_still_running
  end

  before do
    remaining_keys = Resque.redis.keys('sigterm-test:*') || []
    Resque.redis.del(*remaining_keys) unless remaining_keys.empty?
  end

  if !defined?(RUBY_ENGINE) || RUBY_ENGINE != "jruby"
    it "old signal handling just kills off the child" do
      worker_pid, child_pid, result = start_worker(0, false)
      assert_nil result
      assert_child_not_running child_pid
    end

    it "SIGTERM and cleanup occurs in allotted time" do
      worker_pid, child_pid, result = start_worker(0, true)
      assert_exception_caught result
      assert_child_not_running child_pid

      # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
      post_cleanup_occurred = Resque.redis.lpop( 'sigterm-test:ensure_block_executed' )
      assert post_cleanup_occurred, 'post cleanup did not occur. SIGKILL sent too early?'
    end

    it "SIGTERM and cleanup does not occur in allotted time" do
      worker_pid, child_pid, result = start_worker(5, true)
      assert_exception_caught result
      assert_child_not_running child_pid

      # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
      post_cleanup_occurred = Resque.redis.lpop( 'sigterm-test:ensure_block_executed' )
      assert !post_cleanup_occurred, 'post cleanup occurred. SIGKILL sent too late?'
    end
  end

  it "exits with Resque::TermException when using TERM_CHILD and not forking" do
    begin
      ENV['FORK_PER_JOB'] = 'false'
      worker_pid, child_pid, result = start_worker(5, true)
      assert_equal worker_pid, child_pid, "child_pid should equal worker_pid, since we are not forking"
      assert Resque.redis.lpop( 'sigterm-test:ensure_block_executed' ), 'post cleanup did not occur. SIGKILL sent too early?'
    ensure
      ENV['FORK_PER_JOB'] = 'true'
    end
  end

  it "displays warning when not using term_child" do
    worker = Resque::Worker.new(:jobs)
    worker.term_child = nil
    _, stderr = capture_io { worker.work(0) }
    assert stderr.match(/^WARNING:/)
  end

  it "it does not display warning when using term_child" do
    worker = Resque::Worker.new(:jobs)
    worker.term_child = "1"
    _, stderr = capture_io { worker.work(0) }
    assert !stderr.match(/^WARNING:/)
  end
end
