require 'test_helper'

require 'resque/worker'
require 'resque/errors'
require 'socket'

describe Resque::Worker do
  let(:client) { MiniTest::Mock.new }
  let(:awaiter) { MiniTest::Mock.new }

  describe "#initialize" do
    it "contains the correct default options" do
      worker = Resque::Worker.new [:foo, :bar]
      assert_equal worker.options, {:timeout => 5, :interval => 5, :daemon => false, :pid_file => nil, :fork_per_job => true, :run_at_exit_hooks => false }
    end

    it "overrides default options with its parameter" do
      worker = Resque::Worker.new [:foo, :bar], :interval => 10
      assert_equal worker.options, {:timeout => 5, :interval => 10, :daemon => false, :pid_file => nil, :fork_per_job => true, :run_at_exit_hooks => false }
    end

    it "initalizes the specified queues" do
      worker = Resque::Worker.new [:foo, :bar]
      assert_equal worker.queues.size, 2
      assert_equal :foo.to_s, worker.queues.first
      assert_equal :bar.to_s, worker.queues.last
    end

    it "throws NoQueueError when no queues were provided" do
      lambda { worker = Resque::Worker.new }.must_raise(Resque::NoQueueError)
    end
  end

  describe "#state" do
    it "gives us the current state" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, "working")

      worker.stub(:worker_registry, registry) do
        assert_equal "working", worker.state
      end
    end
  end

  describe "#working" do
    it "returns true if the worker is working" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, :working)
      worker.stub(:worker_registry, registry) do
        assert worker.working?
      end
    end

    it "returns false if the worker is not working" do
      worker = Resque::Worker.new [:foo, :bar], :client => client
      registry = MiniTest::Mock.new.expect(:state, :idle)
      worker.stub(:worker_registry, registry) do
        refute worker.working?
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

  describe "#pause" do
    it "will run before_hooks" do
      before_called = false
      Resque.before_pause { before_called = true }

      awaiter.expect(:await, nil)

      worker = Resque::Worker.new(:foo, :client => client, :awaiter => awaiter)

      worker.pause

      assert before_called
    end

    it "will run after_hooks" do
      after_called = false
      Resque.after_pause { after_called = true }

      awaiter.expect(:await, nil)

      worker = Resque::Worker.new(:foo, :client => client, :awaiter => awaiter)

      worker.pause

      assert after_called
    end

    it "no longer paused after pause returns" do
      awaiter.expect(:await, nil)

      worker = Resque::Worker.new(:foo, :client => client, :awaiter => awaiter)

      worker.pause

      refute worker.paused?
    end

  end
end
