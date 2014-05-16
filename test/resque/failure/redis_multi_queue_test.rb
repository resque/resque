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

      failure = Resque::Failure::RedisMultiQueue.all(0, 1, :failed_failed).first
      assert_nil failure['retried_at']

      Resque::Failure::RedisMultiQueue.requeue(0, :failed_failed)

      job = Resque::Job.reserve(:failed)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::RedisMultiQueue.all(0, 1, :failed_failed).first
      refute_nil failure['retried_at']
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

  private

  def save_failure(queue = :failed, klass = 'some_class', args = 'some_args')
    failure = Resque::Failure::RedisMultiQueue.new(Exception.new,
                                         nil, queue,
                                         {'class' => klass,
                                          'args' => args})
    failure.save
  end
end
