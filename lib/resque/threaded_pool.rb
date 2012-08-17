module Resque
  class ThreadedPool

    def initialize(queue, size)
      @queue = queue
      @size  = size
      @threads = []
      @consumers = []
    end


    def start
      stop
      @consumers.clear
      @threads = @size.times.map {
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
