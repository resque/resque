# life cycle management of a job
module Resque
  class ThreadedExecutorPool
    POISON = :poison

    def initialize(queue, pool_size, &block)
      @queue              = queue
      @pool_size          = pool_size
      @threads            = []
      @job_count          = 0
      if block_given?
        @rejected_job_block = block
      else
        @rejected_job_block = proc { raise RejectedJob.new }
      end

      @pool_size.times { @threads << construct_thread }
    end

    def execute(job)
      if @shutdown
        @rejected_job_block.call
      else
        @queue.push(job)
      end
    end

    def shutdown
      @shutdown = true
      @pool_size.times { @queue.push(POISON) }
      @threads.each {|thread| thread.join }
    end

    private
    def construct_thread
      Thread.new {
        while job = @queue.pop
          if job != POISON
            job.run
          else
            break
          end
        end
      }
    end
  end
end
