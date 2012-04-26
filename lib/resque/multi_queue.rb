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
    def initialize(queues, redis = Resque.redis)
      super()

      @queues     = queues # since ruby 1.8 doesn't have Ordered Hashes
      @queue_hash = {}
      @redis      = redis

      queues.each do |queue|
        key = @redis.is_a?(Redis::Namespace) ? "#{@redis.namespace}:" : ""
        key += queue.redis_name
        @queue_hash[key] = queue
      end
    end

    # Pop an item off one of the queues.  This method will block until an item
    # is available. This method returns a tuple of the queue object and job.
    #
    # Pass +true+ for a non-blocking pop.  If nothing is read on a non-blocking
    # pop, a ThreadError is raised.
    def pop(non_block = false)
      if non_block
        synchronize do
          value = nil

          @queues.each do |queue|
            begin
              return [queue, queue.pop(true)]
            rescue ThreadError
            end
          end

          raise ThreadError
        end
      else
        queue_names = @queues.map {|queue| queue.redis_name }
        synchronize do
          value = @redis.blpop(*(queue_names + [1])) until value
          queue_name, payload = value
          queue = @queue_hash[queue_name]
          [queue, queue.decode(payload)]
        end
      end
    end

    # Retrieves data from the queue head, and removes it.
    #
    # Blocks for +timeout+ seconds if the queue is empty, and returns nil if
    # the timeout expires.
    def poll(timeout)
      queue_names = @queues.map {|queue| queue.redis_name }
      queue_name, payload = @redis.blpop(*(queue_names + [timeout]))
      return unless payload

      synchronize do
        queue = @queue_hash[queue_name]
        [queue, queue.decode(payload)]
      end
    end
  end
end
