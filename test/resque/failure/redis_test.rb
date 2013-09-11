require 'test_helper'
require 'resque/failure/redis'

describe Resque::Failure::Redis do
  after do
    Resque.backend.store.flushall
  end

  describe '::all' do
    it 'should return all failures from the :failed queue' do
      save_failure :failed, 'class1'
      save_failure :failed, 'class2'

      result = Resque::Failure::Redis.all
      assert_equal 2, result.count
      assert_equal ['class1', 'class2'],
        result.map { |failure| failure.class_name }
    end

    it 'should return an empty array if there are no items in the :failed queue' do
      result = Resque::Failure::Redis.all
      assert_equal [], result
    end
  end

  describe '#count' do
    it 'should count all failures' do
      save_failure
      save_failure
      save_failure

      assert_equal 3, Resque::Failure::Redis.count
    end

    it 'should count all failures for the given queue and class' do
      save_failure(:failed, 'some_class')
      save_failure(:failed, 'another_class')
      save_failure(:failed, 'another_class')

      assert_equal 1, Resque::Failure::Redis.count(:failed, 'some_class')
      assert_equal 2, Resque::Failure::Redis.count(:failed, 'another_class')
    end
  end

  describe '#queues' do
    it 'should return the failure queue' do
      assert_equal [:failed], Resque::Failure::Redis.queues
    end
  end

  describe '#requeue' do
    it 'should requeue a new job to the queue of the failed job' do
      save_failure

      failure = Resque::Failure::Redis.all.first
      assert_nil failure.retried_at

      Resque::Failure::Redis.requeue(0)

      job = Resque::Job.reserve(:failed)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::Redis.all.first
      refute_nil failure.retried_at
    end
  end

  describe '#requeue_to' do
    it 'should requeue a new job to the desired queue' do
      save_failure

      failure = Resque::Failure::Redis.all.first
      assert_nil failure.retried_at

      Resque::Failure::Redis.requeue_to(0, :new_queue)

      job = Resque::Job.reserve(:new_queue)
      assert_equal 'some_class', job.payload['class']
      assert_equal ['some_args'], job.args

      failure = Resque::Failure::Redis.all.first
      refute_nil failure.retried_at
    end
  end

  describe '#requeue_queue' do
    it 'should requeue all failures for the desired queue' do
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

  describe '#remove_queue' do
    it 'should remove all failures for the desired queue' do
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
