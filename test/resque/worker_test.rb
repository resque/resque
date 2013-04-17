require 'test_helper'

require 'resque/worker'
require 'socket'

describe Resque::Worker do
  describe "#state" do
    it "gives us the current state" do
      client = MiniTest::Mock.new
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, "working")

      worker.stub(:worker_registry, registry) do
        assert_equal "working", worker.state
      end
    end
  end

  describe "#to_s, #inspect" do
    it "gives us string representations of a worker" do
      client = MiniTest::Mock.new

      worker = Resque::Worker.new [:foo, :bar], :client => client
      Socket.stub(:gethostname, "test.com") do
        worker.stub(:pid, "1234") do
          assert_equal "test.com:1234:foo,bar", worker.to_s
          assert_equal "#<Worker test.com:1234:foo,bar>", worker.inspect
        end
      end
    end
  end

  describe "#reconnect" do
    it "delegates to the client" do
      client = MiniTest::Mock.new
      client.expect :reconnect, nil

      worker = Resque::Worker.new :foo, :client => client

      worker.reconnect
    end
  end
end
