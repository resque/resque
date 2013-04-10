require 'test_helper'

require 'resque/worker'

describe Resque::Worker do
  describe "#state" do
    it "gives us the current state" do
      worker = Resque::Worker.new :queue => "foo"
      registry = MiniTest::Mock.new.expect(:state, "working")

      worker.stub(:worker_registry, registry) do
        assert_equal "working", worker.state
      end
    end
  end
end
