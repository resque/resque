require 'test_helper'
require 'resque/failure/redis_multi_queue'

describe Resque::Failure::RedisMultiQueue do
  before do
    Resque::Failure.backend = Resque::Failure::RedisMultiQueue
  end

  after do
    Resque::Failure.backend = nil
    Resque.backend.store.flushall
  end

  describe '::save' do
    it 'saves the failure to the failed queue Redis hash' do
      assert_equal 0, Resque.backend.store.hlen(:queue1_failed)
      save_failure
      assert_equal 1, Resque.backend.store.hlen(:queue1_failed)
    end

    it "saves the failure's redis_id to the failed queue ids list" do
      assert_equal 0, Resque.backend.store.llen(:queue1_failed_ids)
      save_failure
      assert_equal 1, Resque.backend.store.llen(:queue1_failed_ids)
    end

    it 'saves the failed queue name to the :failed_queues set' do
      assert_equal 0, Resque.backend.store.scard(:failed_queues)
      save_failure
      assert_equal 1, Resque.backend.store.scard(:failed_queues)
    end
  end

  describe '::find' do
    it 'returns a failure object with the given id' do
      save_failure :queue2
      failure_id = save_failure.redis_id
      result = Resque::Failure::RedisMultiQueue.find failure_id
      assert_instance_of Resque::Failure, result
      assert_equal failure_id, result.redis_id
    end

    it 'returns a failure object with the given id from the given queue' do
      save_failure :queue2
      failure_id = save_failure.redis_id
      result = Resque::Failure::RedisMultiQueue.find(
        failure_id, :queue => :queue1_failed)
      assert_instance_of Resque::Failure, result
      assert_equal failure_id, result.redis_id
    end

    it 'returns an array of failure objects with the given ids' do
      save_failure :queue2
      failure_ids = 3.times.map { save_failure.redis_id }
      results = Resque::Failure::RedisMultiQueue.find *failure_ids
      assert_instance_of Resque::Failure, results.first
      assert_equal 3, results.size
      assert_equal failure_ids, results.map(&:redis_id).sort
    end

    it 'returns an array of failure objects with the given ids from the given queue' do
      save_failure :queue2
      failure_ids = 3.times.map { save_failure.redis_id }
      results = Resque::Failure::RedisMultiQueue.find(
        *failure_ids, :queue => :queue1_failed)
      assert_instance_of Resque::Failure, results.first
      assert_equal 3, results.size
      assert_equal failure_ids, results.map(&:redis_id).sort
    end

    it 'returns nil if the id does not exist' do
      result = Resque::Failure::RedisMultiQueue.find(42)
      assert_nil result
    end

    it 'returns nil if the id does not exist in the given queue' do
      save_failure :queue2
      failure = save_failure
      result = Resque::Failure::RedisMultiQueue.find(
        failure.redis_id, :queue => :queue2_failed)
      assert_nil result
    end

    it 'always returns an array if multiple ids are given, even if there is only one result' do
      failure = save_failure
      results = Resque::Failure::RedisMultiQueue.find(failure.redis_id, 42)
      assert_instance_of Array, results
      assert_equal 1, results.size
    end

    it 'always returns an array if multiple ids are given, even if there are no results' do
      results = Resque::Failure::RedisMultiQueue.find(42, 43)
      assert_instance_of Array, results
      assert_empty results
    end
  end

  describe '::slice' do
    it 'returns failures with the given offset and limit across all queues' do
      failures_1_ids = 4.times.map { save_failure(:queue1).redis_id }
      failures_2_ids = 4.times.map { save_failure(:queue2).redis_id }
      results = Resque::Failure::RedisMultiQueue.slice 1, 2
      assert_instance_of Hash, results
      assert_equal 2, results.size
      assert_equal failures_1_ids[1, 2], results[:queue1_failed].map(&:redis_id)
      assert_equal failures_2_ids[1, 2], results[:queue2_failed].map(&:redis_id)
    end

    it 'returns failures with the given offset and limit across the given queue' do
      save_failure :queue2
      failure_ids = 4.times.map { save_failure.redis_id }
      results = Resque::Failure::RedisMultiQueue.slice 1, 2, :queue1_failed
      assert_instance_of Array, results
      assert_equal failure_ids[1, 2], results.map(&:redis_id)
    end

    it 'returns an empty array if there are no matching errors' do
      results = Resque::Failure::RedisMultiQueue.slice 1, 2, :queue1_failed
      assert_instance_of Array, results
      assert_empty results
    end
  end

  describe '::requeue' do
    it 'requeues a new job to the queue of the failed job' do
      failure = save_failure
      assert_nil failure.retried_at

      Resque::Failure::RedisMultiQueue.requeue(failure.redis_id)

      job = Resque::Job.reserve(:queue1)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::RedisMultiQueue.find failure.redis_id
      refute_nil failure.retried_at
    end
  end

  describe '::requeue_to' do
    it 'requeues a new job to the desired queue' do
      failure = save_failure
      assert_nil failure.retried_at

      Resque::Failure::RedisMultiQueue.requeue_to(failure.redis_id, :new_queue)

      job = Resque::Job.reserve(:new_queue)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::RedisMultiQueue.find failure.redis_id
      refute_nil failure.retried_at
    end
  end

  describe '::requeue_queue' do
    it 'requeues all failures for the desired queue' do
      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue1')
      save_failure('queue3')

      Resque::Failure::RedisMultiQueue.requeue_queue('queue1')

      2.times do
        job = Resque::Job.reserve('queue1')
        refute_nil job
        assert_equal 'queue1', job.queue
      end

      assert_nil Resque::Job.reserve('queue1')
    end
  end

  describe '::remove_queue' do
    it 'removes all failures for the desired queue' do
      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue1')
      save_failure('queue3')

      Resque::Failure::RedisMultiQueue.remove_queue('queue1')

      assert_equal 0, Resque::Failure.count('queue1_failed')
      assert_equal 1, Resque::Failure.count('queue2_failed')
      assert_equal 1, Resque::Failure.count('queue3_failed')
    end
  end

  describe '::clear' do
    it 'removes all failures in a given queue' do
      save_failure
      save_failure

      assert_equal 2, Resque::Failure.count('queue1_failed')
      assert_equal 2, Resque.backend.store.llen('queue1_failed_ids')
      assert_equal 1, Resque.backend.store.scard('failed_queues')
      Resque::Failure::RedisMultiQueue.clear('queue1_failed')
      assert_equal 0, Resque::Failure.count('queue1_failed')
      assert_equal 0, Resque.backend.store.llen('queue1_failed_ids')
      assert_equal 0, Resque.backend.store.scard('failed_queues')
    end
  end

  describe '::remove' do
    it 'removes an individual failure from the given queue' do
      save_failure
      failure_ids = 2.times.map { save_failure.redis_id }

      assert_equal 3, Resque::Failure.count('queue1_failed')
      assert_equal 3, Resque.backend.store.llen('queue1_failed_ids')
      Resque::Failure::RedisMultiQueue.remove *failure_ids
      assert_equal 1, Resque::Failure.count('queue1_failed')
      assert_equal 1, Resque.backend.store.llen('queue1_failed_ids')
    end
  end

  describe '::queues' do
    it 'lists all known failure queues' do
      assert_empty Resque::Failure::RedisMultiQueue.queues

      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue3')

      expected_queues = ['queue1_failed', 'queue2_failed', 'queue3_failed']
      assert_equal expected_queues, Resque::Failure::RedisMultiQueue.queues.sort
    end
  end

  describe '::count' do
    it 'counts all failures across all failure queues' do
      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue3')

      assert_equal 3, Resque::Failure::RedisMultiQueue.count
    end

    it 'counts all failures for the given queue and class' do
      save_failure('queue1', 'some_class')
      save_failure('queue1', 'another_class')
      save_failure('queue1', 'another_class')

      assert_equal 1, Resque::Failure::RedisMultiQueue.count('queue1_failed', 'some_class')
      assert_equal 2, Resque::Failure::RedisMultiQueue.count('queue1_failed', 'another_class')
    end
  end

  describe '::all' do
    it 'returns an Array of all failures matching a single queue name' do
      # matching
      save_failure('queue1')

      # not matching (fails queue name)
      save_failure('queue2')

      result = Resque::Failure::RedisMultiQueue.all(:queue => :queue1_failed)
      assert_instance_of Array, result
      assert_equal 1, result.size
      assert_equal 'queue1', result.first.queue
    end

    it 'returns a Hash of all failures matching an array of queue names' do
      # matching
      save_failure('queue1')
      save_failure('queue2')

      # not matching (fails queue name)
      save_failure('queue3')

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => [:queue1_failed, :queue2_failed]
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 'queue1', result[:queue1_failed].first.queue
      assert_equal 'queue2', result[:queue2_failed].first.queue
    end

    it 'returns an empty array for no results with a single queue name' do
      result = Resque::Failure::RedisMultiQueue.all(:queue => :foo)
      assert_equal [], result
    end

    it 'returns a hash with empty array values for no results with multiple queues' do
      result = Resque::Failure::RedisMultiQueue.all(:queue => [:foo, :bar])
      assert_equal({ :foo => [], :bar => [] }, result)
    end

    it 'returns all failures matching a single class name' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class1')

      # not matching (fails class name)
      save_failure('queue1', 'class2')

      result = Resque::Failure::RedisMultiQueue.all(:class_name => 'class1')
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'class1', result[:queue1_failed].first.class_name
      assert_equal 'class1', result[:queue2_failed].first.class_name
    end

    it 'returns all failures matching an array of class names' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class2')

      # not matching (fails class name)
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(
        :class_name => ['class1', 'class2']
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'class1', result[:queue1_failed].first.class_name
      assert_equal 'class2', result[:queue2_failed].first.class_name
    end

    it 'returns all failures matching a single queue name and single class name' do
      # matching
      save_failure('queue1', 'class1')

      # not matching
      save_failure('queue1', 'class2') # fails class name
      save_failure('queue2', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => 'queue1_failed',
        :class_name => 'class1'
      )
      assert_instance_of Array, result
      assert_equal 1, result.size
      assert_equal 'queue1', result.first.queue
      assert_equal 'class1', result.first.class_name
    end

    it 'returns all failures matching a single queue name and an array of class names' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')

      # not matching
      save_failure('queue1', 'class3') # fails class name
      save_failure('queue2', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => 'queue1_failed',
        :class_name => ['class1', 'class2']
      ).sort_by { |failure| failure.class_name }
      assert_instance_of Array, result
      assert_equal 2, result.size
      assert_equal 'queue1', result.first.queue
      assert_equal 'class1', result.first.class_name
      assert_equal 'queue1', result.last.queue
      assert_equal 'class2', result.last.class_name
    end

    it 'returns all failures matching an array of queue names and a single class name' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class1')

      # not matching
      save_failure('queue1', 'class2') # fails class name
      save_failure('queue3', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => ['queue1_failed', 'queue2_failed'],
        :class_name => 'class1'
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 'queue1', result[:queue1_failed].first.queue
      assert_equal 'class1', result[:queue1_failed].first.class_name
      assert_equal 'queue2', result[:queue2_failed].first.queue
      assert_equal 'class1', result[:queue2_failed].first.class_name
    end

    it 'returns all failures matching arrays of queue and class names' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class1')
      save_failure('queue2', 'class2')

      # not matching
      save_failure('queue1', 'class3') # fails class name
      save_failure('queue3', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => [:queue1_failed, :queue2_failed],
        :class_name => ['class1', 'class2']
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 2, result[:queue1_failed].size
      assert_equal 2, result[:queue2_failed].size
    end

    it 'offsets the number of failures by the given offset across all queues (single queue exists)' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')

      # matching
      save_failure('queue1', 'class2')
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(:offset => 1)
      assert_instance_of Hash, result
      assert_equal 1, result.size
      assert_equal ['class2', 'class3'],
        result[:queue1_failed].map { |failure| failure.class_name }.sort
    end

    it 'offsets the number of failures by the given offset across all queues (multiple queues exist)' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class3')

      # matching
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class4')

      result = Resque::Failure::RedisMultiQueue.all(:offset => 1)
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 'class2', result[:queue1_failed].first.class_name
      assert_equal 'class4', result[:queue2_failed].first.class_name
    end

    it 'restricts the number of failures to the given limit across all queues (single queue exists)' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')

      # not matching (fails limit)
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(:limit => 2)
      assert_instance_of Hash, result
      assert_equal 1, result.size
      assert_equal ['class1', 'class2'],
        result[:queue1_failed].map { |failure| failure.class_name }.sort
    end

    it 'restricts the number of failures to the given limit across all queues (multiple queues exist)' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class4')
      save_failure('queue2', 'class5')

      # not matching (fails limit)
      save_failure('queue1', 'class3')
      save_failure('queue2', 'class6')

      result = Resque::Failure::RedisMultiQueue.all(:limit => 2)
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal ['class1', 'class2'],
        result[:queue1_failed].map { |failure| failure.class_name }.sort
      assert_equal ['class4', 'class5'],
        result[:queue2_failed].map { |failure| failure.class_name }.sort
    end

    it 'offsets and limits results when given limit and offset options across all queues (single queue exists)' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')

      # matching
      save_failure('queue1', 'class2')

      # not matching (fails limit)
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(:offset => 1, :limit => 1)
      assert_instance_of Hash, result
      assert_equal 1, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'class2', result[:queue1_failed].first.class_name
    end

    it 'offsets and limits results when given limit and offset options across all queues (multiple queues exist)' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class4')

      # matching
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class5')

      # not matching (fails limit)
      save_failure('queue1', 'class3')
      save_failure('queue2', 'class6')

      result = Resque::Failure::RedisMultiQueue.all(:offset => 1, :limit => 1)
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'class2', result[:queue1_failed].first.class_name
      assert_equal 1, result[:queue2_failed].size
      assert_equal 'class5', result[:queue2_failed].first.class_name
    end

    it 'offsets and limits failures from the single given queue' do
      # not matching
      save_failure('queue1', 'class1') # fails offset
      save_failure('queue2', 'class1') # fails offset and queue name

      # matching
      save_failure('queue1', 'class2')

      # not matching
      save_failure('queue1', 'class3') # fails limit
      save_failure('queue2', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :offset => 1,
        :limit => 1,
        :queue => :queue1_failed
      )
      assert_instance_of Array, result
      assert_equal 1, result.size
      assert_equal 'class2', result.first.class_name
    end

    it 'offsets and limits failures from the array of given queues' do
      # not matching
      save_failure('queue1', 'class1') # fails offset
      save_failure('queue2', 'class4') # fails offset
      save_failure('queue3', 'class6') # fails offset and queue name

      # matching
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class5')

      # not matching
      save_failure('queue1', 'class3') # fails limit
      save_failure('queue3', 'class7') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :offset => 1,
        :limit => 1,
        :queue => [:queue1_failed, :queue2_failed]
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'class2', result[:queue1_failed].first.class_name
      assert_equal 1, result[:queue2_failed].size
      assert_equal 'class5', result[:queue2_failed].first.class_name
    end

    it 'offsets and limits failures then filters by the single given class name' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class1')

      # matching
      save_failure('queue1', 'class1', 'arg1')

      # not matching (fails class_name)
      save_failure('queue1', 'class2')
      save_failure('queue2', 'class2')


      result = Resque::Failure::RedisMultiQueue.all(
        :offset => 1,
        :limit => 2,
        :class_name => 'class1'
      )
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 1, result[:queue1_failed].size
      assert_equal 'arg1', result[:queue1_failed].first.args
      assert_equal 0, result[:queue2_failed].size
    end

    it 'offsets and limits failures then filters by the array of given class names' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')
      save_failure('queue2', 'class1')

      # matching
      save_failure('queue1', 'class1', 'arg1')
      save_failure('queue1', 'class2', 'arg2')
      save_failure('queue2', 'class1', 'arg3')

      # not matching
      save_failure('queue1', 'class1') # fails limit
      save_failure('queue2', 'class3') # fails class_name


      result = Resque::Failure::RedisMultiQueue.all(
        :offset => 1,
        :limit => 2,
        :class_name => ['class1', 'class2']
      )
      result[:queue1_failed].sort_by! { |failure| failure.class_name }
      assert_instance_of Hash, result
      assert_equal 2, result.size
      assert_equal 2, result[:queue1_failed].size
      assert_equal 'arg1', result[:queue1_failed].first.args
      assert_equal 'arg2', result[:queue1_failed].last.args
      assert_equal 1, result[:queue2_failed].size
      assert_equal 'arg3', result[:queue2_failed].first.args
    end
  end

  private

  def save_failure(queue = :queue1, klass = 'some_class', args = 'some_args')
    failure = Resque::Failure.create(
      :raw_exception => Exception.new,
      :queue => queue,
      :payload => { 'class' => klass, 'args' => args }
    )
  end
end
