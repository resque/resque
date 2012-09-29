module Resque
  class ThreadedConsumerPool
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
        c = build_consumer @queue
        @consumers << c
        Thread.new { c.consume }
      }
    end

    def stop
      @consumers.each { |c| c.shutdown }
    end

    def join
      @threads.each { |t| t.join }
    end

    def term
      @threads.each { |t| t.raise(TermException.new("SIGTERM")) }
    end

    def kill
      @threads.each { |t| t.kill }
    end

    def pause
      @consumers.each { |c| c.pause }
    end

    def resume
      @consumers.each { |c| c.resume }
    end

    private

    def build_consumer(queue)
      Consumer.new queue
    end
  end
end
