require 'test_helper'

describe "Resque" do
  before do
    @original_redis = Resque.redis
  end

  after do
    Resque.redis = @original_redis
  end

  it "can push an item that depends on redis for encoding" do
    Resque.redis.set("count", 1)
    # No error should be raised
    Resque.push(:test, JsonObject.new)
    Resque.redis.del("count")
  end

  it "can set a namespace through a url-like string" do
    assert Resque.redis
    assert_equal :resque, Resque.redis.namespace
    Resque.redis = 'localhost:9736/namespace'
    assert_equal 'namespace', Resque.redis.namespace
  end

  it "redis= works correctly with a Redis::Namespace param" do
    new_redis = Redis.new(:host => "localhost", :port => 9736)
    new_namespace = Redis::Namespace.new("namespace", :redis => new_redis)
    Resque.redis = new_namespace

    assert_equal new_namespace._client, Resque.redis._client
    assert_equal 0, Resque.size(:default)
  end

  it "can put jobs on a queue" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
  end

  it "can grab jobs off a queue" do
    Resque::Job.create(:jobs, 'some-job', 20, '/tmp')

    job = Resque.reserve(:jobs)

    assert_kind_of Resque::Job, job
    assert_equal SomeJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]
  end

  it "can re-queue jobs" do
    Resque::Job.create(:jobs, 'some-job', 20, '/tmp')

    job = Resque.reserve(:jobs)
    job.recreate

    assert_equal job, Resque.reserve(:jobs)
  end

  it "can put jobs on a queue by way of an ivar" do
    assert_equal 0, Resque.size(:ivar)
    assert Resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert Resque.enqueue(SomeIvarJob, 20, '/tmp')

    job = Resque.reserve(:ivar)

    assert_kind_of Resque::Job, job
    assert_equal SomeIvarJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque.reserve(:ivar)
    assert_equal nil, Resque.reserve(:ivar)
  end

  it "can remove jobs from a queue by way of an ivar" do
    assert_equal 0, Resque.size(:ivar)
    assert Resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert Resque.enqueue(SomeIvarJob, 30, '/tmp')
    assert Resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert Resque::Job.create(:ivar, 'blah-job', 20, '/tmp')
    assert Resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert_equal 5, Resque.size(:ivar)

    assert_equal 1, Resque.dequeue(SomeIvarJob, 30, '/tmp')
    assert_equal 4, Resque.size(:ivar)
    assert_equal 3, Resque.dequeue(SomeIvarJob)
    assert_equal 1, Resque.size(:ivar)
  end

  it "jobs have a nice #inspect" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    job = Resque.reserve(:jobs)
    assert_equal '(Job{jobs} | SomeJob | [20, "/tmp"])', job.inspect
  end

  it "jobs can be destroyed" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 30, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 20, '/tmp')

    assert_equal 5, Resque.size(:jobs)
    assert_equal 2, Resque::Job.destroy(:jobs, 'SomeJob')
    assert_equal 3, Resque.size(:jobs)
    assert_equal 1, Resque::Job.destroy(:jobs, 'BadJob', 30, '/tmp')
    assert_equal 2, Resque.size(:jobs)
  end

  it "jobs can it for equality" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'some-job', 20, '/tmp')
    assert_equal Resque.reserve(:jobs), Resque.reserve(:jobs)

    assert Resque::Job.create(:jobs, 'SomeMethodJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    refute_equal Resque.reserve(:jobs), Resque.reserve(:jobs)

    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 30, '/tmp')
    refute_equal Resque.reserve(:jobs), Resque.reserve(:jobs)
  end

  it "can put jobs on a queue by way of a method" do
    assert_equal 0, Resque.size(:method)
    assert Resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert Resque.enqueue(SomeMethodJob, 20, '/tmp')

    job = Resque.reserve(:method)

    assert_kind_of Resque::Job, job
    assert_equal SomeMethodJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque.reserve(:method)
    assert_equal nil, Resque.reserve(:method)
  end

  it "can define a queue for jobs by way of a method" do
    assert_equal 0, Resque.size(:method)
    assert Resque.enqueue_to(:new_queue, SomeMethodJob, 20, '/tmp')

    job = Resque.reserve(:new_queue)
    assert_equal SomeMethodJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]
  end

  it "needs to infer a queue with enqueue" do
    assert_raises Resque::NoQueueError do
      Resque.enqueue(SomeJob, 20, '/tmp')
    end
  end

  it "validates job for queue presence" do
    err = assert_raises Resque::NoQueueError do
      Resque.validate(SomeJob)
    end
    assert_match(/SomeJob/, err.message)
  end

  it "can put items on a queue" do
    assert Resque.push(:people, { 'name' => 'jon' })
  end

  it "queues are always a list" do
    assert_equal [], Resque.queues
  end

  it "badly wants a class name, too" do
    assert_raises Resque::NoClassError do
      Resque::Job.create(:jobs, nil)
    end
  end

  it "decode bad json" do
    assert_raises Resque::Helpers::DecodeException do
      Resque.decode("{\"error\":\"Module not found \\u002\"}")
    end
  end

  it "inlining jobs" do
    begin
      Resque.inline = true
      Resque.enqueue(SomeIvarJob, 20, '/tmp')
      assert_equal 0, Resque.size(:ivar)
    ensure
      Resque.inline = false
    end
  end

  describe "with people in the queue" do
    before do
      Resque.push(:people, { 'name' => 'chris' })
      Resque.push(:people, { 'name' => 'bob' })
      Resque.push(:people, { 'name' => 'mark' })
    end

    it "can pull items off a queue" do
      assert_equal({ 'name' => 'chris' }, Resque.pop(:people))
      assert_equal({ 'name' => 'bob' }, Resque.pop(:people))
      assert_equal({ 'name' => 'mark' }, Resque.pop(:people))
      assert_equal nil, Resque.pop(:people)
    end

    it "knows how big a queue is" do
      assert_equal 3, Resque.size(:people)

      assert_equal({ 'name' => 'chris' }, Resque.pop(:people))
      assert_equal 2, Resque.size(:people)

      assert_equal({ 'name' => 'bob' }, Resque.pop(:people))
      assert_equal({ 'name' => 'mark' }, Resque.pop(:people))
      assert_equal 0, Resque.size(:people)
    end

    it "can peek at a queue" do
      assert_equal({ 'name' => 'chris' }, Resque.peek(:people))
      assert_equal 3, Resque.size(:people)
    end

    it "can peek multiple items on a queue" do
      assert_equal({ 'name' => 'bob' }, Resque.peek(:people, 1, 1))

      assert_equal([{ 'name' => 'bob' }, { 'name' => 'mark' }], Resque.peek(:people, 1, 2))
      assert_equal([{ 'name' => 'chris' }, { 'name' => 'bob' }], Resque.peek(:people, 0, 2))
      assert_equal([{ 'name' => 'chris' }, { 'name' => 'bob' }, { 'name' => 'mark' }], Resque.peek(:people, 0, 3))
      assert_equal({ 'name' => 'mark' }, Resque.peek(:people, 2, 1))
      assert_equal nil, Resque.peek(:people, 3)
      assert_equal [], Resque.peek(:people, 3, 2)
    end

    it "can delete a queue" do
      Resque.push(:cars, { 'make' => 'bmw' })
      assert_equal %w( cars people ).sort, Resque.queues.sort
      Resque.remove_queue(:people)
      assert_equal %w( cars ), Resque.queues
      assert_equal nil, Resque.pop(:people)
    end

    it "knows what queues it is managing" do
      assert_equal %w( people ), Resque.queues
      Resque.push(:cars, { 'make' => 'bmw' })
      assert_equal %w( cars people ).sort, Resque.queues.sort
    end

    it "keeps track of resque keys" do
      # ignore the heartbeat key that gets set in a background thread
      keys = Resque.keys - ['workers:heartbeat']

      assert_equal ["queue:people", "queues"].sort, keys.sort
    end

    it "keeps stats" do
      Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
      Resque::Job.create(:jobs, BadJob)
      Resque::Job.create(:jobs, GoodJob)

      Resque::Job.create(:others, GoodJob)
      Resque::Job.create(:others, GoodJob)

      stats = Resque.info
      assert_equal 8, stats[:pending]

      @worker = Resque::Worker.new(:jobs)
      @worker.register_worker
      2.times { @worker.work_one_job }

      wt = Resque::WorkerThread.new(@worker)
      @worker.instance_variable_set(:@worker_threads, [ wt ])
      wt.job = @worker.reserve
      wt.set_payload

      stats = Resque.info
      assert_equal 1, stats[:working]
      assert_equal 1, stats[:workers]

      wt.done_working

      stats = Resque.info
      assert_equal 3, stats[:queues]
      assert_equal 3, stats[:processed]
      assert_equal 1, stats[:failed]
      assert_equal [Resque.redis_id], stats[:servers]
    end

  end

  describe "stats" do
    it "queue_sizes with one queue" do
      Resque.enqueue_to(:queue1, SomeJob)

      queue_sizes = Resque.queue_sizes

      assert_equal({ "queue1" => 1 }, queue_sizes)
    end

    it "queue_sizes with two queue" do
      Resque.enqueue_to(:queue1, SomeJob)
      Resque.enqueue_to(:queue2, SomeJob)

      queue_sizes = Resque.queue_sizes

      assert_equal({ "queue1" => 1, "queue2" => 1, }, queue_sizes)
    end

    it "queue_sizes with two queue with multiple jobs" do
      5.times { Resque.enqueue_to(:queue1, SomeJob) }
      9.times { Resque.enqueue_to(:queue2, SomeJob) }

      queue_sizes = Resque.queue_sizes

      assert_equal({ "queue1" => 5, "queue2" => 9 }, queue_sizes)
    end

    it "sample_queues with simple job with no args" do
      Resque.enqueue_to(:queue1, SomeJob)
      queues = Resque.sample_queues

      assert_equal 1, queues.length
      assert_instance_of Hash, queues['queue1']

      assert_equal 1, queues['queue1'][:size]

      samples = queues['queue1'][:samples]
      assert_equal "SomeJob", samples[0]['class']
      assert_equal([], samples[0]['args'])
    end

    it "sample_queues with simple job with args" do
      Resque.enqueue_to(:queue1, SomeJob, :arg1 => '1')

      queues = Resque.sample_queues

      assert_equal 1, queues['queue1'][:size]

      samples = queues['queue1'][:samples]
      assert_equal "SomeJob", samples[0]['class']
      assert_equal([{'arg1' => '1'}], samples[0]['args'])
    end

    it "sample_queues with simple jobs" do
      Resque.enqueue_to(:queue1, SomeJob, :arg1 => '1')
      Resque.enqueue_to(:queue1, SomeJob, :arg1 => '2')

      queues = Resque.sample_queues

      assert_equal 2, queues['queue1'][:size]

      samples = queues['queue1'][:samples]
      assert_equal([{'arg1' => '1'}], samples[0]['args'])
      assert_equal([{'arg1' => '2'}], samples[1]['args'])
    end

    it "sample_queues with more jobs only returns sample size number of jobs" do
      11.times { Resque.enqueue_to(:queue1, SomeJob) }

      queues = Resque.sample_queues(10)

      assert_equal 11, queues['queue1'][:size]

      samples = queues['queue1'][:samples]
      assert_equal 10, samples.count
    end
  end
end
