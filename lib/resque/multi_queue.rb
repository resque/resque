require 'redis'
require 'redis-namespace'
require 'thread'
require 'mutex_m'

module Resque
  ###
  # Holds multiple queues, allowing you to pop the first available job
  class MultiQueue
    include Mutex_m

    ###
    # Create a new MultiQueue using the +queues+ from the +redis+ connection
    def initialize(queues, redis)
      super()

      @queues = {}
      @redis  = redis

      queues.each do |queue|
        key = @redis.is_a?(Redis::Namespace) ? "#{@redis.namespace}:" : ""
        key += queue.redis_name
        @queues[key] = queue
      end
    end

    # Pop an item off one of the queues.  This method will block until an item
    # is available.
    #
    # Pass +true+ for a non-blocking pop.  If nothing is read on a non-blocking
    # pop, a ThreadError is raised.
    def pop(non_block = false)
      if non_block
        synchronize do
          value = nil

          @queues.values.each do |queue|
            begin
              return queue.pop(true)
            rescue ThreadError
            end
          end

          raise ThreadError
        end
      else
        queue_names = @queues.values.map {|queue| queue.redis_name }
        synchronize do
          value = @redis.blpop(*(queue_names + [1])) until value
          queue_name, payload = value
          @queues[queue_name].coder.decode(payload)
        end
      end
    end
  end
end
