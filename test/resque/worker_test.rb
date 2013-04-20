require 'test_helper'

require 'resque/worker'
require 'socket'

describe Resque::Worker do

  let(:client) { MiniTest::Mock.new }

  describe "#state" do
    it "gives us the current state" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, "working")

      worker.stub(:worker_registry, registry) do
        assert_equal "working", worker.state
      end
    end
  end

  describe "#idle" do
    it "returns true if the worker is idle" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, :idle)
      worker.stub(:worker_registry, registry) do
        assert worker.idle?
      end
    end

    it "returns false if the worker is not idle" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, :working)
      worker.stub(:worker_registry, registry) do
        refute worker.idle?
      end
    end
  end

  describe "#to_s, #inspect" do
    it "gives us string representations of a worker" do
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
      client.expect :reconnect, nil
      worker = Resque::Worker.new :foo, :client => client
      worker.reconnect
    end
  end

  describe "#==" do
    it "compares the same worker" do
      worker1 = Resque::Worker.new([:foo], :client => client)
      worker2 = Resque::Worker.new([:foo], :client => client)
      assert worker1 == worker2
    end

    it "compares different workers" do
      worker1 = Resque::Worker.new([:foo], :client => client)
      worker2 = Resque::Worker.new([:bar], :client => client)
      refute worker1 == worker2
    end
  end

  describe "#pid" do
    it "returns the pid of the current process" do
      Process.stub(:pid, 27415) do
        worker = Resque::Worker.new(:foo, :client => client)
        assert 27415, worker.pid
      end
    end
  end
end
