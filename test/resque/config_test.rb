require 'test_helper'

describe Resque::Config do

  describe '#initialize' do
    describe 'with empty hash' do
      let(:args_hash) { {} }

      it 'initializes' do
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
end
