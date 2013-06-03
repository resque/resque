require 'test_helper'
require 'tempfile'
require 'logger'
require 'redis'

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
