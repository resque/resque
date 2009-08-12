require File.dirname(__FILE__) + '/test_helper'

context "Resque::Worker" do
  setup do
    @queue = Resque.new('localhost:6379')
    @queue.redis.flush_all

    @worker = Resque::Worker.new('localhost:6379', :jobs)
    @queue.enqueue(:jobs, SomeJob, 20, '/tmp')
  end

  test "can finish jobs" do
    job = @worker.reserve
    assert job.done
  end

  test "can fail jobs" do
    job = @worker.reserve
    job.fail(Exception.new)
    assert_equal 1, @queue.size("failed")
  end

  test "catches exceptional jobs" do
    @queue.enqueue(:jobs, BadJob)
    @queue.enqueue(:jobs, BadJob)
    @worker.process
    @worker.process
    @worker.process
    assert_equal 2, @queue.size("failed")
  end

  test "can work on multiple queues" do
    @queue.enqueue(:high, GoodJob)
    @queue.enqueue(:critical, GoodJob)

    worker = Resque::Worker.new('localhost:6379', :critical, :high)

    worker.process
    assert_equal 1, @queue.size(:high)
    assert_equal 0, @queue.size(:critical)

    worker.process
    assert_equal 0, @queue.size(:high)
  end

  test "has a unique id" do
    assert_equal "#{$$}:#{`hostname`.chomp}", @worker.to_s
  end
end
