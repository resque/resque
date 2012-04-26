module Resque
  class Consumer
    class Latch # :nodoc:
      def initialize
        @mutex = Mutex.new
        @cond  = ConditionVariable.new
      end

      def release
        @mutex.synchronize { @cond.broadcast }
      end

      def await
        @mutex.synchronize { @cond.wait @mutex }
      end
    end

    def initialize(queue, timeout = 5)
      @queue           = queue
      @should_pause    = false
      @should_shutdown = false
      @paused          = false
      @shutdown        = false
      @timeout         = timeout
      @latch           = Latch.new
    end

    def consume
      loop do
        suspend if @should_pause

        if @should_shutdown
          @shutdown = true
          break
        end

        queue, job = @queue.poll(@timeout)
        next unless job
        job.run
      end
    end

    def pause
      @should_pause = true
    end

    def paused?
      @paused
    end

    def shutdown?
      @shutdown
    end

    def resume
      @should_pause = false
      @paused       = false
      @latch.release
    end
    
    def shutdown
      @should_shutdown = true
    end

    private
    def suspend
      @paused = true
      @latch.await
    end
  end
end
