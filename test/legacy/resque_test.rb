require 'test_helper'

describe "Resque" do
  before do
    resque = Resque.new
    resque.backend.store.flushall

    resque.push(:people, { 'name' => 'chris' })
    resque.push(:people, { 'name' => 'bob' })
    resque.push(:people, { 'name' => 'mark' })
    Resque::Worker.__send__(:public, :done_working)
    @original_redis = resque.backend.store
  end

  after do
    resque.redis = @original_redis
  end

  it "can put jobs on a queue" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
  end

  it "can grab jobs off a queue" do
    Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')

    job = Resque::Job.reserve(:jobs)

    assert_kind_of Resque::Job, job
    assert_equal SomeJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]
  end

  it "can re-queue jobs" do
    Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')

    job = Resque::Job.reserve(:jobs)
    job.recreate

    assert_equal job, Resque::Job.reserve(:jobs)
  end

  it "can put jobs on a queue by way of an ivar" do
    assert_equal 0, resque.size(:ivar)
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')

    job = Resque::Job.reserve(:ivar)

    assert_kind_of Resque::Job, job
    assert_equal SomeIvarJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque::Job.reserve(:ivar)
    assert_equal nil, Resque::Job.reserve(:ivar)
  end

  it "can remove jobs from a queue by way of an ivar" do
    assert_equal 0, resque.size(:ivar)
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert resque.enqueue(SomeIvarJob, 30, '/tmp')
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert Resque::Job.create(:ivar, 'blah-job', 20, '/tmp')
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert_equal 5, resque.size(:ivar)

    assert_equal 1, resque.dequeue(SomeIvarJob, 30, '/tmp')
    assert_equal 4, resque.size(:ivar)
    assert_equal 3, resque.dequeue(SomeIvarJob)
    assert_equal 1, resque.size(:ivar)
  end

  it "can find queued jobs by way of an ivar" do
    assert resque.enqueue(SomeIvarJob, 20, '/tmp')
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert resque.enqueue(SomeIvarJob, 30, '/tmp')

    expected_jobs = [
      Resque::Job.new(:ivar, {'class' => SomeIvarJob, 'args' => [20, '/tmp']}),
      Resque::Job.new(:ivar, {'class' => SomeIvarJob, 'args' => [30, '/tmp']})
    ]

    assert_equal expected_jobs, resque.queued(SomeIvarJob)
    assert_equal 2, resque.queued(SomeIvarJob).size
    assert_equal 1, resque.queued(SomeIvarJob, 20, '/tmp').size
    assert_equal 1, resque.queued(SomeIvarJob, 30, '/tmp').size
    assert_equal 1, resque.queued(SomeMethodJob, 20, '/tmp').size
  end

  it "jobs have a nice #inspect" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    job = Resque::Job.reserve(:jobs)
    assert_equal '(Job{jobs} | SomeJob | [20, "/tmp"])', job.inspect
  end

  it "jobs can be destroyed" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 30, '/tmp')
    assert Resque::Job.create(:jobs, 'BadJob', 20, '/tmp')

    assert_equal 5, resque.size(:jobs)
    assert_equal 2, Resque::Job.destroy(:jobs, 'SomeJob')
    assert_equal 3, resque.size(:jobs)
    assert_equal 1, Resque::Job.destroy(:jobs, 'BadJob', 30, '/tmp')
    assert_equal 2, resque.size(:jobs)
  end

  it "jobs can it for equality" do
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert_equal Resque::Job.reserve(:jobs), Resque::Job.reserve(:jobs)

    assert Resque::Job.create(:jobs, 'SomeMethodJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    refute_equal Resque::Job.reserve(:jobs), Resque::Job.reserve(:jobs)

    assert Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
    assert Resque::Job.create(:jobs, 'SomeJob', 30, '/tmp')
    refute_equal Resque::Job.reserve(:jobs), Resque::Job.reserve(:jobs)
  end

  it "can put jobs on a queue by way of a method" do
    assert_equal 0, resque.size(:method)
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')

    job = Resque::Job.reserve(:method)

    assert_kind_of Resque::Job, job
    assert_equal SomeMethodJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque::Job.reserve(:method)
    assert_equal nil, Resque::Job.reserve(:method)
  end

  it "can define a queue for jobs by way of a method" do
    assert_equal 0, resque.size(:method)
    assert resque.enqueue_to(:new_queue, SomeMethodJob, 20, '/tmp')

    job = Resque::Job.reserve(:new_queue)
    assert_equal SomeMethodJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]
  end

  it "needs to infer a queue with enqueue" do
    assert_raises Resque::NoQueueError do
      resque.enqueue(JobNotAmI, 20, '/tmp')
    end
  end

  it "validates job for queue presence" do
    assert_raises Resque::NoQueueError do
      resque.validate(JobNotAmI)
    end
  end

  it "can put jobs on a queue inferred from class name ending in 'Worker'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(InferredWorker, 20, '/tmp')
    assert resque.enqueue(InferredWorker, 20, '/tmp')

    job = Resque::Job.reserve(:inferred)

    assert_kind_of Resque::Job, job
    assert_equal InferredWorker, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque::Job.reserve(:inferred)
    assert_equal nil, Resque::Job.reserve(:inferred)
  end

  it "can put jobs on a queue inferred from class name ending in 'Job'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(InferredJob, 20, '/tmp')
    assert resque.enqueue(InferredJob, 20, '/tmp')

    job = Resque::Job.reserve(:inferred)

    assert_kind_of Resque::Job, job
    assert_equal InferredJob, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque::Job.reserve(:inferred)
    assert_equal nil, Resque::Job.reserve(:inferred)
  end

  it "can put jobs on a queue inferred from namespaced class name ending in 'Job'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(Inferred::Job, 20, '/tmp')
    assert resque.enqueue(Inferred::Job, 20, '/tmp')

    job = Resque::Job.reserve(:inferred)

    assert_kind_of Resque::Job, job
    assert_equal Inferred::Job, job.payload_class
    assert_equal 20, job.args[0]
    assert_equal '/tmp', job.args[1]

    assert Resque::Job.reserve(:inferred)
    assert_equal nil, Resque::Job.reserve(:inferred)
  end

  it "can remove jobs from a queue inferred from class name ending in 'Worker'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(InferredWorker, 20, '/tmp')
    assert resque.enqueue(InferredWorker, 30, '/tmp')
    assert resque.enqueue(InferredWorker, 20, '/tmp')
    assert Resque::Job.create(:inferred, 'blah-job', 20, '/tmp')
    assert resque.enqueue(InferredWorker, 20, '/tmp')
    assert_equal 5, resque.size(:inferred)

    assert_equal 1, resque.dequeue(InferredWorker, 30, '/tmp')
    assert_equal 4, resque.size(:inferred)
    assert_equal 3, resque.dequeue(InferredWorker)
    assert_equal 1, resque.size(:inferred)
  end

  it "can remove jobs from a queue inferred from class name ending in 'Job'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(InferredJob, 20, '/tmp')
    assert resque.enqueue(InferredJob, 30, '/tmp')
    assert resque.enqueue(InferredJob, 20, '/tmp')
    assert Resque::Job.create(:inferred, 'blah-job', 20, '/tmp')
    assert resque.enqueue(InferredJob, 20, '/tmp')
    assert_equal 5, resque.size(:inferred)

    assert_equal 1, resque.dequeue(InferredJob, 30, '/tmp')
    assert_equal 4, resque.size(:inferred)
    assert_equal 3, resque.dequeue(InferredJob)
    assert_equal 1, resque.size(:inferred)
  end

  it "can remove jobs from a queue inferred from namespaced class name ending in 'Job'" do
    assert_equal 0, resque.size(:inferred)
    assert resque.enqueue(Inferred::Job, 20, '/tmp')
    assert resque.enqueue(Inferred::Job, 30, '/tmp')
    assert resque.enqueue(Inferred::Job, 20, '/tmp')
    assert Resque::Job.create(:inferred, 'blah-job', 20, '/tmp')
    assert resque.enqueue(Inferred::Job, 20, '/tmp')
    assert_equal 5, resque.size(:inferred)

    assert_equal 1, resque.dequeue(Inferred::Job, 30, '/tmp')
    assert_equal 4, resque.size(:inferred)
    assert_equal 3, resque.dequeue(Inferred::Job)
    assert_equal 1, resque.size(:inferred)
  end

  it "can find queued jobs inferred from class name ending in 'Worker'" do
    assert resque.enqueue(InferredWorker, 20, '/tmp')
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert resque.enqueue(InferredWorker, 30, '/tmp')

    expected_jobs = [
      Resque::Job.new(:inferred, {'class' => InferredWorker, 'args' => [20, '/tmp']}),
      Resque::Job.new(:inferred, {'class' => InferredWorker, 'args' => [30, '/tmp']})
    ]

    #assert_equal expected_jobs, resque.queued(InferredWorker)
    assert_equal 2, resque.queued(InferredWorker).size
    assert_equal 1, resque.queued(InferredWorker, 20, '/tmp').size
    assert_equal 1, resque.queued(InferredWorker, 30, '/tmp').size
    assert_equal 1, resque.queued(SomeMethodJob, 20, '/tmp').size
  end

  it "can find queued jobs inferred from class name ending in 'Job'" do
    assert resque.enqueue(InferredJob, 20, '/tmp')
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert resque.enqueue(InferredJob, 30, '/tmp')

    expected_jobs = [
      Resque::Job.new(:inferred, {'class' => InferredJob, 'args' => [20, '/tmp']}),
      Resque::Job.new(:inferred, {'class' => InferredJob, 'args' => [30, '/tmp']})
    ]

    #assert_equal expected_jobs, resque.queued(InferredJob)
    assert_equal 2, resque.queued(InferredJob).size
    assert_equal 1, resque.queued(InferredJob, 20, '/tmp').size
    assert_equal 1, resque.queued(InferredJob, 30, '/tmp').size
    assert_equal 1, resque.queued(SomeMethodJob, 20, '/tmp').size
  end

  it "can find queued jobs inferred from namespaced class name ending in 'Job'" do
    assert resque.enqueue(Inferred::Job, 20, '/tmp')
    assert resque.enqueue(SomeMethodJob, 20, '/tmp')
    assert resque.enqueue(Inferred::Job, 30, '/tmp')

    expected_jobs = [
      Resque::Job.new(:inferred, {'class' => Inferred::Job, 'args' => [20, '/tmp']}),
      Resque::Job.new(:inferred, {'class' => Inferred::Job, 'args' => [30, '/tmp']})
    ]

    #assert_equal expected_jobs, resque.queued(Inferred::Job)
    assert_equal 2, resque.queued(Inferred::Job).size
    assert_equal 1, resque.queued(Inferred::Job, 20, '/tmp').size
    assert_equal 1, resque.queued(Inferred::Job, 30, '/tmp').size
    assert_equal 1, resque.queued(SomeMethodJob, 20, '/tmp').size
  end

  it "can put items on a queue" do
    assert resque.push(:people, { 'name' => 'jon' })
  end

  it "can pull items off a queue" do
    assert_equal({ 'name' => 'chris' }, resque.pop(:people))
    assert_equal({ 'name' => 'bob' }, resque.pop(:people))
    assert_equal({ 'name' => 'mark' }, resque.pop(:people))
    assert_equal nil, resque.pop(:people)
  end

  it "knows how big a queue is" do
    assert_equal 3, resque.size(:people)

    assert_equal({ 'name' => 'chris' }, resque.pop(:people))
    assert_equal 2, resque.size(:people)

    assert_equal({ 'name' => 'bob' }, resque.pop(:people))
    assert_equal({ 'name' => 'mark' }, resque.pop(:people))
    assert_equal 0, resque.size(:people)
  end

  it "can peek at a queue" do
    assert_equal([{ 'name' => 'chris' }], resque.peek(:people))
    assert_equal 3, resque.size(:people)
  end

  it "can peek multiple items on a queue" do
    assert_equal([{ 'name' => 'bob' }], resque.peek(:people, 1, 1))

    assert_equal([{ 'name' => 'bob' }, { 'name' => 'mark' }], resque.peek(:people, 1, 2))
    assert_equal([{ 'name' => 'chris' }, { 'name' => 'bob' }], resque.peek(:people, 0, 2))
    assert_equal([{ 'name' => 'chris' }, { 'name' => 'bob' }, { 'name' => 'mark' }], resque.peek(:people, 0, 3))
    assert_equal([{ 'name' => 'mark' }], resque.peek(:people, 2, 1))
    assert_equal [], resque.peek(:people, 3)
    assert_equal [], resque.peek(:people, 3, 2)
  end

  it "knows what queues it is managing" do
    assert_equal %w( people ), resque.queues
    resque.push(:cars, { 'make' => 'bmw' })
    assert_equal %w( cars people ).sort, resque.queues.sort
  end

  it "queues are always a list" do
    resque.backend.store.flushall
    assert_equal [], resque.queues
  end

  it "can delete a queue" do
    resque.push(:cars, { 'make' => 'bmw' })
    assert_equal %w( cars people ).sort, resque.queues.sort
    resque.remove_queue(:people)
    assert_equal %w( cars ), resque.queues
    assert_equal nil, resque.pop(:people)
  end

  it "keeps track of resque keys" do
    assert_equal ["queue:people", "queues"].sort, resque.keys.sort
  end

  it "badly wants a class name, too" do
    assert_raises Resque::NoClassError do
      Resque::Job.create(:jobs, nil)
    end
  end

  it "keeps stats" do
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, GoodJob)

    Resque::Job.create(:others, GoodJob)
    Resque::Job.create(:others, GoodJob)

    stats = resque.info
    assert_equal 8, stats[:pending]

    @worker = Resque::Worker.new(:jobs)
    registry = Resque::WorkerRegistry.new(@worker)
    registry.register
    2.times { @worker.process }

    job = @worker.__send__(:reserve)
    registry = Resque::WorkerRegistry.new(@worker)
    registry.working_on @worker, job

    stats = resque.info
    assert_equal 1, stats[:working]
    assert_equal 1, stats[:workers]

    @worker.done_working

    stats = resque.info
    assert_equal 3, stats[:queues]
    assert_equal 3, stats[:processed]
    assert_equal 1, stats[:failed]
    if ENV.key? 'RESQUE_DISTRIBUTED'
      assert_equal [resque.backend.store.respond_to?(:server) ? 'localhost:9736, localhost:9737' : 'redis://localhost:9736/0, redis://localhost:9737/0'], stats[:servers]
    else
      assert_equal [resque.backend.store.respond_to?(:server) ? 'localhost:9736' : 'redis://localhost:9736/0'], stats[:servers]
    end
  end

  it "decode bad json" do
    assert_raises Resque::DecodeException do
      resque.coder.decode("{\"error\":\"Module not found \\u002\"}")
    end
  end

  it "inlining jobs" do
    begin
      resque.inline = true
      resque.enqueue(SomeIvarJob, 20, '/tmp')
      assert_equal 0, resque.size(:ivar)
    ensure
      resque.inline = false
    end
  end

  it "inlining jobs in inline job" do
    begin
      resque.inline = true
      resque.enqueue(NestedJob)
      assert_equal 0, resque.size(:ivar)
    ensure
      resque.inline = false
    end
  end

  it "inlining jobs with block" do
    resque.inline do
      resque.enqueue(SomeIvarJob, 20, '/tmp')
    end
    assert_equal 0, resque.size(:ivar)
    assert !resque.inline?
  end

  it "inline block sets inline to false after exception" do
    assert_raises StandardError do
      resque.inline do
        raise StandardError
      end
    end
    assert !resque.inline?
  end

  it "inline block doesn't change inline to false if already inline" do
    begin
      resque.inline = true
      resque.inline { }
      assert resque.inline?
    ensure
      resque.inline = false
    end
  end

  it "inline without block is alias to inline?" do
    begin
      assert_equal resque.inline?, resque.inline
      resque.inline = true
      assert_equal resque.inline?, resque.inline
    ensure
      resque.inline = false
    end
  end

  it 'treats symbols and strings the same' do
    assert_equal resque.queue(:people), resque.queue('people')
  end
end
