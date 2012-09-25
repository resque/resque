require "test_helper"

module Resque

  describe "ThreadedConsumerPool" do

    class Actionable
      @@ran = []

      def self.ran
        @@ran
      end

      def run
        self.class.ran << self
      end
    end

    class FailingJob
      def run
        raise 'fuuu'
      end
    end

    before do
      @write  = Queue.new(:foo)
      @read  = Queue.new(:foo, Resque.pool)
      @tp = ThreadedConsumerPool.new(@read, 5)
    end

    it "processes work" do
      Resque.consumer_timeout = 1
      5.times { @write << Actionable.new }
      @tp.start
      sleep 1
      @tp.stop
      assert @write.empty?
    end

    it "recovers from blowed-up jobs" do
      Resque.consumer_timeout = 1
      @tp = ThreadedConsumerPool.new(@read, 1)
      @write << FailingJob.new
      @write << Actionable.new

      @tp.start
      sleep 1
      @tp.stop
      assert @write.empty?
    end

  end
end
