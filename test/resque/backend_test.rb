require 'test_helper'
require 'tempfile'

require 'resque/backend'

describe Resque::Backend do
  let(:logger) { Logger.new(Tempfile.new('resque-log')) }

  describe "#new" do
    it "needs a Redis to be built" do
      redis = MiniTest::Mock.new
      backend = Resque::Backend.new(redis, logger)

      assert_same backend.store.__id__, redis.__id__
    end
  end

  describe "::connect" do
    it "can take a redis://... string" do
      redis = Resque::Backend::connect('redis://localhost:9736')
      assert_equal :resque, redis.namespace
      assert_equal 9736, redis.client.port
      assert_equal 'localhost', redis.client.host
    end

    it "can set a namespace through a url-like string" do
      redis = Resque::Backend::connect('localhost:9736/namespace')
      assert redis
      assert_equal 'namespace', redis.namespace
    end

    it "works correctly with a Redis::Namespace param" do
      bare_redis = Redis.new(:host => "localhost", :port => 9736)
      namespace = Redis::Namespace.new("namespace", :redis => bare_redis)
      redis = Resque::Backend.connect(namespace)
      assert_equal namespace, redis
    end

    it "works with Redis::Distributed" do
      distributed = Redis::Distributed.new(%w(redis://localhost:6379 redis://localhost:6380))
      redis = Resque::Backend.connect(distributed)
      assert_equal distributed, redis
    end
  end

  describe "#reconnect" do
    it "attempts to retry three times" do
      redis = Class.new do
        def client
          @client ||= Class.new do
            attr_accessor :count
            
            def reconnect
              @count ||= 0
              @count += 1
              raise Redis::BaseConnectionError
            end
          end.new
        end
      end.new

      client = Resque::Backend.new(redis, logger)

      # not actually stubbing right now?
      Kernel.stub(:sleep, nil) do
        rescued = false

        begin
          client.reconnect
        rescue Resque::Backend::ConnectionError
          rescued = true
          assert_equal 3, client.store.client.count
        end

        assert rescued
      end

    end
  end
end
