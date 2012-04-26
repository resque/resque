module Resque
  class Consumer
    def initialize(queue)
      @queue = queue
    end

    def consume
      while job = @queue.pop
        job.run
      end
    end

    def pause
    end

    def shutdown
    end
  end
end
