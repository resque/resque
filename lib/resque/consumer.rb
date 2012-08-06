module Resque
  class Consumer
    class Latch # :nodoc:
      def initialize(count = 1)
        @count = count
        @lock  = Monitor.new
        @cv    = @lock.new_cond
      end

      def release
        @lock.synchronize do
          @count -= 1 if @count > 0
          @cv.broadcast if @count.zero?
        end
      end

      def await
        @lock.synchronize do
          @cv.wait_while { @count > 0 }
        end
      end
    end

    def initialize(queue, timeout = Resque.consumer_timeout)
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
