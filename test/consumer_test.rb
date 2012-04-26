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
    end
  end
end
