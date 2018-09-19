require 'test_helper'
require 'tmpdir'

describe "Resque::Worker" do

  class LongRunningJob
    @queue = :long_running_job

    def self.perform
      Resque.redis.reconnect # get its own connection
      Resque.redis.rpush('sigterm-test:start', Process.pid)
      sleep 5
      Resque.redis.rpush('sigterm-test:result', 'Finished Normally')
    ensure
      Resque.redis.rpush('sigterm-test:ensure_block_executed', 'exiting.')
    end
  end

  def hostname
    @hostname ||= Socket.gethostname
  end

  def start_worker
    Resque.enqueue LongRunningJob

    worker_pid = Kernel.fork do
      Resque.redis.reconnect
      worker = Resque::Worker.new(:long_running_job)
      suppress_warnings do
        worker.work(0)
      end
      exit!
    end

    # ensure the worker is started
    start_status = Resque.redis.blpop('sigterm-test:start', 5)
    refute_nil start_status
    child_pid = start_status[1].to_i
    assert child_pid > 0, "worker child process not created"

    [worker_pid, child_pid]
  end

  def assert_child_not_running(child_pid)
    assert (`ps -p #{child_pid.to_s} -o pid=`).empty?
  end

  it "kills off the child when killed" do
    worker_pid, child_pid = start_worker
    assert worker_pid != child_pid
    Process.kill('TERM', worker_pid)
    Process.waitpid(worker_pid)

    result = Resque.redis.lpop('sigterm-test:result')
    assert_nil result
    assert_child_not_running child_pid
  end

  it "kills workers via the remote kill mechanism" do
    worker_pid, child_pid = start_worker
    thread = Resque::WorkerManager.find_thread("#{hostname}:#{worker_pid}:long_running_job:1")
    thread.kill
    sleep 3

    result = Resque.redis.lpop('sigterm-test:result')
    assert_nil result
  end

  it "runs if not killed" do
    worker_pid, child_pid = start_worker

    result = Resque.redis.blpop('sigterm-test:result')
    assert 'Finished Normally' == result.last
  end
end
