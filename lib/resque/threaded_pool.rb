module Resque
  class ThreadedPool

    def initialize(queue, pool)
      @queue = queue
      @pool  = pool
      @threads = []
      @consumers = []
    end


    def start
      @consumers.clear
      @threads = @pool.times.map {
        c = Consumer.new(@queue)
        @consumers << c
        Thread.new { c.consume }
      }
    end

    def stop
      @consumers.each { |c| c.shutdown }
      @threads.each { |t| t.join }
    end
  end
end
