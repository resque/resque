require "test_helper"

Thread.abort_on_exception = true

module Resque

  describe "ThreadedPool" do

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
      @write  = Queue.new(:foo)
      conn = Resque.create_connection(Resque.server)
      @read  = Queue.new(:foo, conn)
      @tp = ThreadedPool.new(@read, 5)
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
      skip
    end

  end
end
