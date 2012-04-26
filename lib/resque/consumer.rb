module Resque
  class Consumer
    def initialize(queue, timeout = 5)
      @queue        = queue
      @should_pause = false
      @paused       = false
      @timeout      = timeout
    end

    def consume
      loop do
        suspend if @should_pause

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
    
    def shutdown
    end

    private
    def suspend
      @paused = true
      sleep
    end
  end
end
