require 'test_helper'

require 'resque/client'

describe Resque::Client do
  let(:logger) { Logger.new(Tempfile.new('resque-log')) }

  describe "#new" do
    it "needs a Redis to be built" do
      redis = MiniTest::Mock.new
      client = Resque::Client.new(redis, logger)

      assert_same client.backend.__id__, redis.__id__
    end
  end

  describe "#reconnect" do
    it "attempts to retry three times" do
      redis = Class.new do
        def client
          @client ||= Class.new do
            def reconnect
              @count ||= 0
              return if @count == 2

              @count += 1
              raise Redis::BaseConnectionError
            end
          end.new
        end
      end.new

      client = Resque::Client.new(redis, logger)

      # not actually stubbing right now?
      Kernel.stub(:sleep, nil) do
        client.reconnect
      end
    end
  end
end
