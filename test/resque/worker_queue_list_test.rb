require 'test_helper'

require 'resque/globals'
require 'resque/worker_queue_list'

describe Resque::WorkerQueueList do
  describe "#initialize" do
   it "accepts a single queue name" do
     worker_queue_list = Resque::WorkerQueueList.new(:bar)
     assert_equal 1, worker_queue_list.queues.length
   end

   it "requires exactly one argument" do
     assert_raises(ArgumentError) { Resque::WorkerQueueList.new }
   end

   it "constructs an empty queue from an empty array" do
     worker_queue_list = Resque::WorkerQueueList.new([])
     assert_equal 0, worker_queue_list.queues.length
   end
  end

  describe "#empty?" do
    it "is true when queues are empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert worker_queue_list.empty?
    end

    it "is false when queues contain a value" do
      worker_queue_list = Resque::WorkerQueueList.new(:foo)
      refute worker_queue_list.empty?
    end
  end

  describe "#size" do
    it "is zero when empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert_equal 0, worker_queue_list.size
    end

    it "returns the correct count when populated" do
      worker_queue_list = Resque::WorkerQueueList.new(:foo)
      assert_equal 1, worker_queue_list.size
    end
  end

  describe "#first" do
    it "is nil when queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert_nil worker_queue_list.first
    end

    it "is the first queue in the order when list is non-empty" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      assert_equal "foo", worker_queue_list.first
    end
  end

  describe "#to_s" do
    it "is the empty string when queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert_equal "", worker_queue_list.to_s
    end

    it "is a comma seperated list of queue names" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      assert_equal "foo,bar,stuff", worker_queue_list.to_s
    end
  end

  describe "#search_order" do
    it "is an empty array when the queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert_empty worker_queue_list.search_order
    end

    it "is equal to the list of queue names when names do not contain splats" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      assert_equal ["foo", "bar", "stuff"], worker_queue_list.search_order
    end

    it "generates an alphabetically ordered list of dynamic queues for splats" do
      worker_queue_list = Resque::WorkerQueueList.new("*")
      Resque.stub(:queues, ["foo", "bar", "stuff"]) do
        assert_equal ["bar", "foo", "stuff"], worker_queue_list.search_order
      end
    end

    it "puts dynamic queues (splats) in front" do
      worker_queue_list = Resque::WorkerQueueList.new(["*", :last])
      Resque.stub(:queues, ["foo", "bar", "stuff"]) do
        assert_equal ["bar", "foo", "stuff", "last"], worker_queue_list.search_order
      end
    end
  end
end
