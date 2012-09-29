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
    def initialize(queues, pool = Resque.pool)
      super()

      @queues     = queues # since ruby 1.8 doesn't have Ordered Hashes
      @queue_hash = {}
      @pool       = pool
      @pool.with_connection { |redis|
        @namespace = redis.is_a?(Redis::Namespace) ? redis.namespace : nil
      }

      queues.each do |queue|
        key = [@namespace, queue.redis_name].compact.join(':')
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
        if queue_names.any?
          synchronize do
            value = @pool.with_connection {|pool| pool.blpop(*(queue_names + [:timeout => 1])) } until value
            queue_name, payload = value
            queue = @queue_hash["#{@namespace}:#{queue_name}"]
            [queue, queue.decode(payload)]
          end
        else
          Kernel.sleep # forever
        end
      end
    end

    # Retrieves data from the queue head, and removes it.
    #
    # Blocks for +timeout+ seconds if the queue is empty, and returns nil if
    # the timeout expires.
    def poll(timeout)
      queue_names = @queues.map {|queue| queue.redis_name }
      if queue_names.any?
        queue_name, payload = @pool.with_connection {|pool| pool.blpop(*(queue_names + [:timeout => timeout])) }
        return unless payload

        synchronize do
          key = [@namespace, queue_name].compact.join ':'
          queue = @queue_hash[key]
          [queue, queue.decode(payload)]
        end
      else
        Kernel.sleep(timeout)
        nil
      end
    end
  end
end
