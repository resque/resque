require 'test_helper'

require 'resque/client'

describe Resque::Client do
  describe "#new" do
    it "needs a Redis to be built" do
      redis = MiniTest::Mock.new
      client = Resque::Client.new(redis)

      assert_same client.backend.__id__, redis.__id__
    end
  end
end
