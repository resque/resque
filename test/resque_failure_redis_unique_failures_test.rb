require 'test_helper'
require 'resque/failure/redis_unique_failures'

describe 'Resque::Failure::RedisUniqueFailures' do
  let(:bad_string) { [39, 52, 127, 86, 93, 95, 39].map(&:chr).join }
  let(:exception)  { StandardError.exception(bad_string) }
  let(:worker)     { Resque::Worker.new(:test) }
  let(:queue)      { 'queue' }
  let(:payload)    { { 'class' => 'Object', 'args' => 3 } }
  let(:redis_backend_instance) do
    Resque::Failure::RedisUniqueFailures.new(
      exception, worker, queue, payload
    )
  end
  let(:another_redis_backend_instance) do
    Resque::Failure::RedisUniqueFailures.new(
      exception, worker, queue, payload_with_different_order
    )
  end

  describe '#save' do
    describe 'with duplicates' do
      it 'saves the failure only once' do
        redis_backend_instance.save
        redis_backend_instance.save
        assert_equal 1, Resque::Failure::RedisUniqueFailures.count
      end
    end

    describe 'with payload in different order' do
      let(:payload_with_different_order) { { 'args' => 3, 'class' => 'Object' } }

      it 'saves the failure only once' do
        redis_backend_instance.save
        another_redis_backend_instance.save
        assert_equal 1, Resque::Failure::RedisUniqueFailures.count
      end
    end

    describe 'with nested hashes in the payload' do
      let(:payload) do
        {
          'class' => 'Object',
          'args' => { 'first_name' => 'Peter', 'last_name' => 'Parker' }
        }
      end
      let(:payload_with_different_order) do
        {
          'args' => { 'last_name' => 'Parker', 'first_name' => 'Peter' },
          'class' => 'Object'
        }
      end

      it 'saves the failure only once' do
        redis_backend_instance.save
        another_redis_backend_instance.save
        assert_equal 1, Resque::Failure::RedisUniqueFailures.count
      end
    end
  end
end
