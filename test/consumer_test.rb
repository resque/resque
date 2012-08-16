require "test_helper"

module Resque
  describe "Consumer" do
    class Actionable
      @@ran = []

      def self.ran
        @@ran
      end

      def run
        self.class.ran << self
      end
    end

    class Resumer
      LATCHES = {}

      def initialize(latch)
        @latch_id          = latch.object_id
        LATCHES[@latch_id] = latch
      end

      def run
        LATCHES[@latch_id].release
      end
    end

    class Poison
      CONSUMERS = {}

      def initialize(consumer)
        @consumer_id            = consumer.object_id
        CONSUMERS[@consumer_id] = consumer
      end

      def run
        CONSUMERS[@consumer_id].shutdown
      end
    end

    before do
      Actionable.ran.clear
    end

    it "consumes jobs" do
      q = Queue.new(:foo)
      q << Actionable.new
      c = Consumer.new(q)


      # avoid using begin / rescue
      assert_raises Timeout::Error do
        Timeout.timeout(1) { c.consume }
      end

      assert_equal 1, Actionable.ran.length
      assert q.empty?
    end

    it "pauses" do
      q = Queue.new(:foo)
      c = Consumer.new(q, 1)

      t = Thread.new { c.consume }
      # wait until queue blocks
      Thread.pass until t.status == "sleep"

      c.pause
      sleep 2.1 # wait until poll times out
      assert c.paused?

      q << Actionable.new
      # Wait until timeout seconds to make sure our job isn't
      # consumed
      sleep 2
      assert_equal 1, q.length
      q << Poison.new(c)
    end

    it "resumes" do
      q = Queue.new(:foo)
      q.pop until q.empty?

      c = Consumer.new(q, 1)
      consumed = Consumer::Latch.new

      c.pause
      t = Thread.new { c.consume }
      Thread.pass until c.paused?

      # A job that unblocks the main thread
      q << Resumer.new(consumed)
      c.resume

      # wait until consumed
      consumed.await

      assert_equal 0, q.length, 'all jobs should be consumed'
      q << Poison.new(c) # gracefully shutdown the consumer
    end

    it "shuts down" do
      q = Queue.new(:foo)
      c = Consumer.new(q, 1)
      t = Thread.new { c.consume }
      # wait until queue blocks
      Thread.pass until t.status == "sleep"
      c.shutdown

      # sleep past the poll timeout
      sleep 2
      q << Actionable.new
      # sleep past the poll timeout
      sleep 2
      assert_equal 1, q.length
      assert c.shutdown?
      q.pop until q.empty?
      q << Poison.new(c)
    end
  end
end
