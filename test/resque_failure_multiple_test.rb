require 'test_helper'
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'resque/failure/redis_multi_queue'

describe 'Resque::Failure::Multiple' do
  class BrokenBackend < Resque::Failure::Base
    class OriginalError < RuntimeError
    end

    def save
      raise OriginalError, "Raise error always"
    end
  end

  let(:exception) { StandardError.exception('some error') }
  let(:worker)    { Resque::Worker.new(:test) }
  let(:payload)   { { 'class' => 'Object', 'args' => 3 } }

  it 'saves every backend under an assigned failure_id' do
    Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::RedisMultiQueue]
    multiple = Resque::Failure::Multiple.new(exception, worker, 'queue', payload)
    multiple.failure_id = 'shared-id'
    multiple.save

    backends = multiple.instance_variable_get(:@backends)
    assert_equal ['shared-id', 'shared-id'], backends.map(&:failure_id)
  end

  it 'saves every backend under its own generated failure_id' do
    Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::RedisMultiQueue]
    multiple = Resque::Failure::Multiple.new(exception, worker, 'queue', payload)
    multiple.save

    generated = multiple.failure_id
    backends = multiple.instance_variable_get(:@backends)
    assert_equal [generated, generated], backends.map(&:failure_id)
  end

  it 'records the same failure_id in every backend' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::RedisMultiQueue]
      Resque::Failure.create(:exception => exception, :worker => worker,
                             :queue => 'queue', :payload => payload)

      from_redis = Resque::Failure::Redis.all(0)
      from_multi_queue = Resque::Failure::RedisMultiQueue.all(0, 1, Resque::Failure.failure_queue_name('queue'))

      refute_nil from_redis['failure_id']
      assert_equal from_redis['failure_id'], from_multi_queue['failure_id']
    end
  end

  it 'does not require its backends to accept a failure_id' do
    backend_class = Class.new do
      def initialize(exception, worker, queue, payload); end
      def save; end
    end

    Resque::Failure::Multiple.classes = [backend_class]
    multiple = Resque::Failure::Multiple.new(exception, worker, 'queue', payload)
    multiple.failure_id = 'shared-id'
    multiple.save # should not raise

    assert_equal 'shared-id', multiple.failure_id
  end

  it 'requeue_all and does not raise an exception' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [Resque::Failure::Redis]

      Resque::Failure.create({:exception => exception, :worker => worker, :queue => 'queue', :payload => payload})
      Resque::Failure::Multiple.requeue_all # should not raise an error
    end
  end

  it 'call #save to all backends even if some backends fail' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [BrokenBackend, Resque::Failure::Redis]
      Resque::Failure::Redis.any_instance.expects(:save)

      assert_raises(Resque::Failure::Multiple::BackendError) {
        Resque::Failure.create({:exception => exception, :worker => worker, :queue => 'queue', :payload => payload})
      }
    end
  end

  it 'raises BackendError with original error when some backends fail' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [BrokenBackend, Resque::Failure::Redis]

      begin
        Resque::Failure.create({:exception => exception, :worker => worker, :queue => 'queue', :payload => payload})
      rescue Resque::Failure::Multiple::BackendError => err
        assert_equal err.original_errors.keys.size, 1
        assert_instance_of BrokenBackend::OriginalError, err.original_errors[BrokenBackend]
      else
        raise "Expect to raise BackendError but not raised"
      end
    end
  end

  it 'requeue_queue delegates to the first class and returns a mapped queue name' do
    with_failure_backend(Resque::Failure::Multiple) do
      mock_class = Minitest::Mock.new
      mock_class.expect(:requeue_queue, 'mapped_queue', ['queue'])
      Resque::Failure::Multiple.classes = [mock_class]
      assert_equal 'mapped_queue', Resque::Failure::Multiple.requeue_queue('queue')
    end
  end

  it 'remove passes the queue on to its backend' do
    with_failure_backend(Resque::Failure::Multiple) do
      mock = Object.new
      def mock.remove(_id, queue)
        @queue = queue
      end

      Resque::Failure::Multiple.classes = [mock]
      Resque::Failure::Multiple.remove(1, :test_queue)
      assert_equal :test_queue, mock.instance_variable_get('@queue')
    end
  end
end
