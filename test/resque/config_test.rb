require 'test_helper'

describe Resque::Config do
  let(:config){ Resque::Config.new }

  describe "#redis=" do

    it "can take a redis://... string" do
      config.redis = 'redis://localhost:9736'
      assert_equal :resque, config.redis.namespace
      assert_equal 9736, config.redis.client.port
      assert_equal 'localhost', config.redis.client.host
    end

    it "can set a namespace through a url-like string" do
      config.redis = Redis.new
      assert config.redis
      assert_equal :resque, config.redis.namespace
      config.redis = 'localhost:9736/namespace'
      assert_equal 'namespace', config.redis.namespace
    end

    it "works correctly with a Redis::Namespace param" do
      new_redis = Redis.new(:host => "localhost", :port => 9736)
      new_namespace = Redis::Namespace.new("namespace", :redis => new_redis)
      config.redis = new_namespace
      assert_equal new_namespace, config.redis
    end

    it "works with Redis::Distributed" do
      distributed = Redis::Distributed.new(%w(redis://localhost:6379 redis://localhost:6380))
      config.redis = distributed
      assert_equal distributed, config.redis
    end
  end

  describe "#redis_id" do
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
