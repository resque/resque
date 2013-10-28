require 'test_helper'
require 'resque/multi_queue'

describe Resque::MultiQueue do
  describe ".from_queues" do
    it "constructs a multiqueue from list of queues" do
      multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
      assert multi_queue.respond_to?(:pop)
    end
  end

  describe "#pop" do
    it "raises ThreadError when empty and non-blocking" do
      multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
      assert_raises(ThreadError) {
        multi_queue.pop(true)
      }
    end

    it "returns a tuple when non-empty and non-blocking" do
      queue = Resque::Queue.new(:foo, Resque.backend.store, Resque.coder)
      queue.push "Cowabonga!"
      Resque::Queue.stub :new, queue do
        multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
        tuple = multi_queue.pop(true)
        assert_equal 2, tuple.size
        assert_equal queue, tuple[0]
        assert_equal "Cowabonga!", tuple[1]
      end
    end

   it "returns a tuple when non-empty and blocking" do
      queue = Resque::Queue.new(:foo, Resque.backend.store, Resque.coder)
      queue.push "Cowabonga!"
      Resque::Queue.stub :new, queue do
        multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
        tuple = multi_queue.pop
        assert_equal 2, tuple.size
        assert_equal queue, tuple[0]
        assert_equal "Cowabonga!", tuple[1]
      end
    end
  end

  describe "#poll" do
    it "returns nil when queue is empty after timeout" do
        multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
        result = multi_queue.poll(1)
        assert result.nil?
    end

   it "returns a tuple when queue is non-empty" do
      queue = Resque::Queue.new(:foo, Resque.backend.store, Resque.coder)
      queue.push "Cowabonga!"
      Resque::Queue.stub :new, queue do
        multi_queue = Resque::MultiQueue.from_queues([:foo, :bar])
        tuple = multi_queue.poll(1)
        assert_equal 2, tuple.size
        assert_equal queue, tuple[0]
        assert_equal "Cowabonga!", tuple[1]
      end
    end

  end
end
