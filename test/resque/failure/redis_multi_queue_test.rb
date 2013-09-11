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

  describe '#requeue' do
    it 'requeues a new job to the queue of the failed job' do
      save_failure

      failure = Resque::Failure::RedisMultiQueue.slice(0, 1, :failed_failed).first
      assert_nil failure.retried_at

      Resque::Failure::RedisMultiQueue.requeue(0, :failed_failed)

      job = Resque::Job.reserve(:failed)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::RedisMultiQueue.slice(0, 1, :failed_failed).first
      refute_nil failure.retried_at
    end
  end

  describe '#requeue_queue' do
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

  describe '#remove_queue' do
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

  describe '#clear' do
    it 'removes all failures in a given queue' do
      save_failure('queue1')
      save_failure('queue1')

      assert_equal 2, Resque::Failure.count('queue1_failed')
      Resque::Failure::RedisMultiQueue.clear('queue1_failed')
      assert_equal 0, Resque::Failure.count('queue1_failed')
    end
  end

  describe '#remove' do
    it 'removes an individual failure from the given queue' do
      save_failure('queue1')

      assert_equal 1, Resque::Failure.count('queue1_failed')
      Resque::Failure::RedisMultiQueue.remove(0, 'queue1_failed')
      assert_equal 0, Resque::Failure.count('queue1_failed')
    end
  end

  describe '#queues' do
    it 'lists all known failure queues' do
      assert_empty Resque::Failure::RedisMultiQueue.queues

      save_failure('queue1')
      save_failure('queue2')
      save_failure('queue3')

      expected_queues = ['queue1_failed', 'queue2_failed', 'queue3_failed']
      assert_equal expected_queues, Resque::Failure::RedisMultiQueue.queues.sort
    end
  end

  describe '#count' do
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
  
  describe '#all' do
    it 'should return an Array of all failures matching a single queue name' do
      # matching
      save_failure('queue1')

      # not matching (fails queue name)
      save_failure('queue2')

      result = Resque::Failure::RedisMultiQueue.all(:queue => :queue1_failed)
      assert_instance_of Array, result
      assert_equal 1, result.size
      assert_equal 'queue1', result.first.queue
    end

    it 'should return a Hash of all failures matching an array of queue names' do
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

    it 'should return an empty array for no results with a single queue name' do
      result = Resque::Failure::RedisMultiQueue.all(:queue => :foo)
      assert_equal [], result
    end

    it 'should return a hash with empty array values for no results with multiple queues' do
      result = Resque::Failure::RedisMultiQueue.all(:queue => [:foo, :bar])
      assert_equal({ :foo => [], :bar => [] }, result)
    end

    it 'should return all failures matching a single class name' do
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

    it 'should return all failures matching an array of class names' do
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

    it 'should return all failures matching a single queue name and single class name' do
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

    it 'should return all failures matching a single queue name and an array of class names' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')

      # not matching
      save_failure('queue1', 'class3') # fails class name
      save_failure('queue2', 'class1') # fails queue name

      result = Resque::Failure::RedisMultiQueue.all(
        :queue => 'queue1_failed',
        :class_name => ['class1', 'class2']
      )
      assert_instance_of Array, result
      assert_equal 2, result.size
      assert_equal 'queue1', result.first.queue
      assert_equal 'class1', result.first.class_name
      assert_equal 'queue1', result.last.queue
      assert_equal 'class2', result.last.class_name
    end

    it 'should return all failures matching an array of queue names and a single class name' do
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

    it 'should return all failures matching arrays of queue and class names' do
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

    it 'should offset the number of failures by the given offset across all queues (single queue exists)' do
      # not matching (fails offset)
      save_failure('queue1', 'class1')

      # matching
      save_failure('queue1', 'class2')
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(:offset => 1)
      assert_instance_of Hash, result
      assert_equal 1, result.size
      assert_equal ['class2', 'class3'],
        result[:queue1_failed].map { |failure| failure.class_name }
    end

    it 'should offset the number of failures by the given offset across all queues (multiple queues exist)' do
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

    it 'should restrict the number of failures to the given limit across all queues (single queue exists)' do
      # matching
      save_failure('queue1', 'class1')
      save_failure('queue1', 'class2')

      # not matching (fails limit)
      save_failure('queue1', 'class3')

      result = Resque::Failure::RedisMultiQueue.all(:limit => 2)
      assert_instance_of Hash, result
      assert_equal 1, result.size
      assert_equal ['class1', 'class2'],
        result[:queue1_failed].map { |failure| failure.class_name }
    end

    it 'should restrict the number of failures to the given limit across all queues (multiple queues exist)' do
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
        result[:queue1_failed].map { |failure| failure.class_name }
      assert_equal ['class4', 'class5'],
        result[:queue2_failed].map { |failure| failure.class_name }
    end

    it 'should offset and limit results when given limit and offset options across all queues (single queue exists)' do
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

    it 'should offset and limit results when given limit and offset options across all queues (multiple queues exist)' do
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

    it 'should offset and limit failures from the single given queue' do
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

    it 'should offset and limit failures from the array of given queues' do
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

    it 'should offset and limit failures then filter by the single given class name' do
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

    it 'should offset and limit failures then filter by the array of given class names' do
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

  def save_failure(queue = :failed, klass = 'some_class', args = 'some_args')
    failure = Resque::Failure.create(
      :raw_exception => Exception.new,
      :queue => queue,
      :payload => { 'class' => klass, 'args' => args }
    )
  end
end
