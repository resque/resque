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
    assert_equal "#{`hostname`.chomp}:#{$$}", @worker.to_s
  end

  test "complains if no queues are given" do
    assert_raise Resque::Worker::NoQueueError do
      Resque::Worker.new('localhost:6379')
    end
  end

  test "inserts itself into the 'workers' list on startup" do
    @worker.register_worker
    assert_equal @worker.to_s, @queue.workers[0]
  end

  test "removes itself from the 'workers' list on shutdown" do
    @worker.register_worker
    assert_equal @worker.to_s, @queue.workers[0]

    @worker.unregister_worker
    assert_equal [], @queue.workers
  end

  test "records what it is working on" do
    job = @worker.reserve
    @worker.working_on job
    task = @queue.worker(@worker.to_s)
    assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
    assert task['run_at']
    assert_equal 'jobs', task['queue']
  end

  test "clears its status when not working on anything" do
    job = @worker.reserve
    @worker.working_on job
    assert @queue.worker(@worker.to_s)

    @worker.done_working
    assert_equal nil, @queue.worker(@worker.to_s)
  end

  test "knows when it is working" do
    job = @worker.reserve
    @worker.working_on job
    assert @queue.worker(@worker.to_s)

    assert_equal :working, @queue.worker_state(@worker.to_s)
  end

  test "knows when it is idle" do
    job = @worker.reserve
    @worker.working_on job
    assert @queue.worker(@worker.to_s)

    @worker.done_working
    assert_equal :idle, @queue.worker_state(@worker.to_s)
  end
end
