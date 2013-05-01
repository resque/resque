require 'test_helper'

require 'resque/worker_queue_list'

describe Resque::WorkerQueueList do

  describe "#initialize" do
   it "constructs an array of queue names" do
     worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar])
     worker_queue_list.queues.must_be_instance_of Array
   end

   it "contstructs an array for a single queue" do
     worker_queue_list = Resque::WorkerQueueList.new(:bar)
     worker_queue_list.queues.must_be_instance_of Array
   end

   it "requires exactly one argument" do
     proc {Resque::WorkerQueueList.new}.must_raise ArgumentError
   end

   it "constructs an empty queue from an empty array" do
     worker_queue_list = Resque::WorkerQueueList.new([])
     worker_queue_list.queues.must_be_instance_of Array
   end
  end

  describe "#empty?" do
    it "is true when queues is nil" do
      # The WorkerQueueList constructor requires an argument, so we cheat
      subclass = Class.new(Resque::WorkerQueueList) do
        def initialize
        end
      end
      assert subclass.new.empty?
    end

    it "is true when queues are empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      assert worker_queue_list.empty?
    end

    it "is false when queues contain a value" do
      worker_queue_list = Resque::WorkerQueueList.new(:foo)
      worker_queue_list.empty?.must_equal false
    end
  end

  describe "#size" do
    it "is zero when empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      worker_queue_list.size.must_equal 0
    end

    it "returns the correct count when populated" do
      worker_queue_list = Resque::WorkerQueueList.new(:foo)
      worker_queue_list.size.must_equal 1
    end
  end

  describe "#first" do
    it "is nil when queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      worker_queue_list.first.must_be_nil
    end

    it "is the first queue in the order when list is non-empty" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      worker_queue_list.first.must_equal "foo"
    end
  end

  describe "#to_s" do
    it "is the empty string when queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      worker_queue_list.to_s.must_equal ""
    end

    it "is a comma seperated list of queue names" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      worker_queue_list.to_s.must_equal "foo,bar,stuff"
    end
  end

  describe "#search_order" do
    it "is an empty array when the queue list is empty" do
      worker_queue_list = Resque::WorkerQueueList.new([])
      worker_queue_list.search_order.must_equal []
    end

    it "is equal to the list of queue names when names do not contain splats" do
      worker_queue_list = Resque::WorkerQueueList.new([:foo, :bar, :stuff])
      worker_queue_list.search_order.must_equal ["foo", "bar", "stuff"]
    end

    it "generates an alphabetically ordered list of dynamic queues for splats" do
      worker_queue_list = Resque::WorkerQueueList.new("*")
      Resque.stub(:queues, ["foo", "bar", "stuff"]) do
        worker_queue_list.search_order.must_equal ["bar", "foo", "stuff"]
      end
    end

    it "puts dynamic queues (splats) in front" do
      worker_queue_list = Resque::WorkerQueueList.new(["*", :last])
      Resque.stub(:queues, ["foo", "bar", "stuff"]) do
        worker_queue_list.search_order.must_equal ["bar", "foo", "stuff", "last"]
      end
    end
  end
end
