require "test_helper"

module Resque
  describe "ThreadedExecutorPool" do
    class Actionable
      attr_reader :ran

      def initialize
        @ran = false
      end

      def run
        @ran = true
      end
    end

    class WaitingJob
      attr_reader :ran

      def initialize(worker_latch, main_latch)
        @worker_latch = worker_latch
        @main_latch   = main_latch
        @ran          = false
      end

      def run
        @main_latch.release
        @worker_latch.await
        @ran = true
      end
    end

    class SecondJob
      attr_reader :ran

      def initialize(latch)
        @latch = latch
        @ran   = false
      end

      def run
        @latch.release
        @ran = true
      end
    end

    it "can be constructed" do
      assert ThreadedExecutorPool.new(::Queue.new, 1)
    end

    it "runs the job" do
      pool = ThreadedExecutorPool.new(::Queue.new, 1)
      job  = Actionable.new
      pool.execute(job)
      pool.shutdown

      assert job.ran
    end

    it "shuts down" do
      pool = ThreadedExecutorPool.new(::Queue.new, 1)
      job  = Actionable.new
      pool.shutdown

      assert_raises(RejectedJob) { pool.execute(job) }
      assert !job.ran
    end

    it "calls block when executing a job on a shutdown pool" do
      a    = 1
      pool = ThreadedExecutorPool.new(::Queue.new, 1) { a = 2 }
      job  = Actionable.new
      pool.shutdown

      pool.execute(job)

      assert !job.ran
      assert_equal 2, a
    end

    it "runs the jobs concurrently" do
      pool          = ThreadedExecutorPool.new(::Queue.new, 2)
      waiting_latch = Consumer::Latch.new
      main_latch    = Consumer::Latch.new
      waiting_job   = WaitingJob.new(waiting_latch, main_latch)
      second_job    = SecondJob.new(waiting_latch)

      pool.execute(waiting_job)
      Timeout.timeout(1) { main_latch.await }
      pool.execute(second_job)
      pool.shutdown

      assert waiting_job.ran
      assert second_job.ran
    end
  end
end
