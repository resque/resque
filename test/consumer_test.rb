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
  end
end
