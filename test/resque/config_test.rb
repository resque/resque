require 'test_helper'
require 'mock_redis'

describe Resque::Config do
  
  describe '#initialize' do
    describe 'with empty hash' do
      let(:args_hash) { {} }
      
      it 'should initialize' do
        Resque::Config::new(args_hash)
      end
    end
  end

  describe "#redis_id" do
    let(:config) { Resque::Config.new }
  
    it "redis" do
      redis = Redis.new
      config.redis = redis
      assert_equal config.redis_id, redis.client.id
    end

    it "distributed" do
      require 'redis/distributed'
      config.redis = Redis::Distributed.new(%w(redis://localhost:6379 redis://localhost:6380))
      assert_equal config.redis_id, "redis://localhost:6379/0, redis://localhost:6380/0"
    end
  end

  describe '#redis' do
    describe 'when the underlying connection doesn\'t exist' do
      it 'should raise' do
        config.redis = nil
        assert_raises(RuntimeError) { config.redis }
      end
    end
    describe 'when the underlying connection is a redis connection' do
      it 'should not raise' do
        redis_connection = Redis::Namespace.new(:resque, :redis => MockRedis.new)
        config.redis = redis_connection
        assert_equal redis_connection, config.redis
      end
    end
  end
end
