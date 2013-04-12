require 'test_helper'

describe Resque::Config do
  let(:config){ Resque::Config.new }

  describe "#redis=" do
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
  end

  describe "#redis_id" do
    it "redis 1.x" do
      config.stub(:redis, MiniTest::Mock.new.expect(:server, "server")) do
        assert_equal config.redis_id, "server"
      end
    end

    it "redis 2.x" do
      redis = Redis.new
      config.redis = redis
      assert_equal config.redis_id, redis.client.id
    end
  end
end