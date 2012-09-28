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

    class TermJob
      LATCHES = {}

      @@termed = []

      def self.clear
        @@termed = []
      end

      def self.termed
        @@termed
      end

      attr_reader :latch_id

      def initialize(latch)
        @latch_id          = latch.object_id
        LATCHES[@latch_id] = latch
      end

      def == other
        return super unless other.is_a?(TermJob)
        @latch_id == other.latch_id
      end

      def run
        begin
          LATCHES[@latch_id].release
          sleep
        rescue Resque::TermException
          @@termed << self
        end
      end
    end

    before do
      @write  = Queue.new(:foo)
      @read  = Queue.new(:foo, Resque.pool)
      @tp = ThreadedConsumerPool.new(@read, 5)
      TermJob.clear
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
      @tp.join
    end

    it "terms the consumers" do
      @tp   = ThreadedConsumerPool.new(@read, 1)
      latch = Consumer::Latch.new
      job   = TermJob.new latch
      @write << job

      @tp.start
      latch.await # sleep until latch#release is called
      @tp.term
      @tp.stop
      @tp.join

      assert_equal job, TermJob.termed.first
      assert @read.empty?
    end

    it "kills running jobs" do
      @tp = ThreadedConsumerPool.new(@read, 1)
      latch = Consumer::Latch.new
      job = TermJob.new latch
      @write << job

      @tp.start
      latch.await
      @tp.kill
      @tp.join

      assert TermJob.termed.empty?
      assert @read.empty?
    end

    it "pauses and resumes" do
      paused = []
      resumed = []

      @tp = Class.new(ThreadedConsumerPool) {
        define_method(:build_consumer) { |q|
          super(q).extend(Module.new {
            define_method(:pause) { paused << self; super() }
            define_method(:resume) { resumed << self; super() }
          })
        }
      }.new(@read, 1)

      @tp.start
      @tp.pause
      assert_equal 1, paused.length

      @tp.resume
      assert_equal 1, resumed.length
      @tp.stop
      @tp.join
    end
  end
end
