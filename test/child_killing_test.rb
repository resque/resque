require 'test_helper'
require 'tmpdir'

describe "Resque::Worker" do

  class LongRunningJob
    @queue = :long_running_job

    def self.perform
      Resque.redis.reconnect # get its own connection
      Resque.redis.rpush('sigterm-test:start', Process.pid)
      sleep 10
      Resque.redis.rpush('sigterm-test:result', 'Finished Normally')
    ensure
      Resque.redis.rpush('sigterm-test:ensure_block_executed', 'exiting.')
    end
  end

  def start_worker
    Resque.enqueue LongRunningJob

    worker_pid = Kernel.fork do
      # reconnect since we just forked
      Resque.redis.reconnect

      worker = Resque::Worker.new(:long_running_job)

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
    result = Resque.redis.lpop('sigterm-test:result')
    [worker_pid, child_pid, result]
  end

  def assert_child_not_running(child_pid)
    assert (`ps -p #{child_pid.to_s} -o pid=`).empty?
  end

  it "kills off the child when killed" do
    _worker_pid, child_pid, result = start_worker
    assert_nil result
    assert_child_not_running child_pid
  end
end
