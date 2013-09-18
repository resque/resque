require 'test_helper'
require 'resque/failure/redis'

describe Resque::Failure::Redis do
  after do
    Resque.backend.store.flushall
  end

  describe '::save' do
    it 'saves the failure to the :failed Redis hash' do
      assert_equal 0, Resque.backend.store.hlen(:failed)
      save_failure
      assert_equal 1, Resque.backend.store.hlen(:failed)
    end

    it "saves the failure's redis_id to the :failed_ids list" do
      assert_equal 0, Resque.backend.store.zcard(:failed_ids)
      save_failure
      assert_equal 1, Resque.backend.store.zcard(:failed_ids)
    end
  end

  describe '::all' do
    it 'returns all failures from the :failed queue' do
      save_failure :failed, 'class1'
      save_failure :failed, 'class2'

      result = Resque::Failure::Redis.all
      assert_equal 2, result.count
      assert_equal ['class1', 'class2'],
        result.map { |failure| failure.class_name }.sort
    end

    it 'returns an empty array if there are no items in the :failed queue' do
      result = Resque::Failure::Redis.all
      assert_equal [], result
    end
  end

  describe '::find' do
    it 'returns a failure object with the given id' do
      failure_id = save_failure.redis_id
      result = Resque::Failure::Redis.find failure_id
      assert_instance_of Resque::Failure, result
      assert_equal failure_id, result.redis_id
    end

    it 'returns an array of failure objects with the given ids' do
      failure_ids = 3.times.map { save_failure.redis_id }
      results = Resque::Failure::Redis.find *failure_ids
      assert_instance_of Resque::Failure, results.first
      assert_equal 3, results.size
      assert_equal failure_ids, results.map(&:redis_id)
    end

    it 'returns nil if the id does not exist' do
      result = Resque::Failure::Redis.find(42)
      assert_nil result
    end

    it 'always returns an array if multiple ids are given, even if there is only one result' do
      failure_id = save_failure.redis_id
      results = Resque::Failure::Redis.find(failure_id, 42)
      assert_instance_of Array, results
      assert_equal 1, results.size
    end
  end

  describe '::slice' do
    it 'returns failures with the given offset and limit from the :failed queue' do
      failure_ids = 4.times.map { save_failure.redis_id }
      results = Resque::Failure::Redis.slice 1, 2
      assert_equal 2, results.size
      assert_equal failure_ids[1, 2], results.map(&:redis_id)
    end

    it 'returns an empty array if there are no matching errors' do
      results = Resque::Failure::Redis.slice 1, 2
      assert_instance_of Array, results
      assert_empty results
    end
  end

  describe '::clear' do
    it 'deletes the :failed hash and the :failed_ids list from Redis' do
      save_failure
      assert Resque.backend.store.exists(:failed)
      assert Resque.backend.store.exists(:failed_ids)
      Resque::Failure::Redis.clear
      refute Resque.backend.store.exists(:failed)
      refute Resque.backend.store.exists(:failed_ids)
    end
  end

  describe '::count' do
    it 'counts all failures' do
      3.times { save_failure }
      assert_equal 3, Resque::Failure::Redis.count
    end

    it 'counts all failures for the given queue and class' do
      save_failure(:failed, 'some_class')
      save_failure(:failed, 'another_class')
      save_failure(:failed, 'another_class')

      assert_equal 1, Resque::Failure::Redis.count(:failed, 'some_class')
      assert_equal 2, Resque::Failure::Redis.count(:failed, 'another_class')
    end
  end

  describe '::queues' do
    it 'returns the failure queue' do
      assert_equal [:failed], Resque::Failure::Redis.queues
    end
  end

  describe '::requeue' do
    it 'requeues a new job to the queue of the failed job' do
      failure = save_failure
      assert_nil failure.retried_at

      Resque::Failure::Redis.requeue(failure.redis_id)

      job = Resque::Job.reserve(:failed)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::Redis.find failure.redis_id
      refute_nil failure.retried_at
    end
  end

  describe '::requeue_to' do
    it 'requeues a new job to the desired queue' do
      failure = save_failure
      assert_nil failure.retried_at

      Resque::Failure::Redis.requeue_to(failure.redis_id, :new_queue)

      job = Resque::Job.reserve(:new_queue)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::Redis.find failure.redis_id
      refute_nil failure.retried_at
    end
  end

  describe '::requeue_queue' do
    it 'requeues all failures for the desired queue' do
      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue1')
      save_failure('queue3')

      Resque::Failure::Redis.requeue_queue('queue1')

      2.times do
        job = Resque::Job.reserve('queue1')
        refute_nil job
        assert_equal 'queue1', job.queue
      end

      assert_nil Resque::Job.reserve('queue1')
    end
  end

  describe '::remove' do
    it 'removes failures with the given ids' do
      save_failure
      failure_ids = 2.times.map { save_failure.redis_id }

      assert_equal 3, Resque.backend.store.zcard(:failed_ids)
      assert_equal 3, Resque.backend.store.hlen(:failed)
      Resque::Failure::Redis.remove *failure_ids
      assert_equal 1, Resque.backend.store.zcard(:failed_ids)
      assert_equal 1, Resque.backend.store.hlen(:failed)
    end
  end

  describe '::remove_queue' do
    it 'removes all failures for the desired queue' do
      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue1')
      save_failure('queue3')

      Resque::Failure::Redis.remove_queue('queue1')

      assert_equal 2, Resque::Failure.count
      assert_equal 'queue2', Resque::Failure::Redis.slice(0).first.queue
      assert_equal 'queue3', Resque::Failure::Redis.slice(1).first.queue
    end
  end

  private

  def save_failure(queue = :failed, klass = 'some_class', args = 'some_args')
    failure = Resque::Failure.create(
      :raw_exception => Exception.new,
      :queue => queue,
      :payload => { 'class' => klass, 'args' => args }
    )
  end
end
