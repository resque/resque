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
      @q_list = queues

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
          queue_name, payload = @redis.blpop(*(queue_names + [0]))

          raise ThreadError unless queue_name && payload
          @queues[queue_name].decode(payload)
        end
      else
        synchronize do
          value = @redis.blpop(*(queue_names + [1])) until value
          queue_name, payload = value
          @queues[queue_name].decode(payload)
        end
      end
    end

    private
    def queue_names
      # possibly refactor this to set an ivar of the list in the constructor.
      # We don't need to calculate the list on every call to `pop`.
      @q_list.map {|queue| queue.redis_name }
    end
  end
end
