require 'redis'
require 'redis-namespace'
require 'thread'
require 'mutex_m'

module Resque
  ###
  # A queue interface that quacks like Queue from Ruby's stdlib.
  class Queue
    include Mutex_m

    ###
    # Create a new Queue object with +name+ on +redis+ connection, and using
    # the +coder+ for encoding and decoding objects that are stored in redis.
    def initialize name, redis, coder = Marshal
      super()
      @name  = "queue:#{name}"
      @redis = redis
      @coder = coder
    end

    # Add +object+ to the queue
    def push object
      synchronize do
        @redis.rpush @name, encode(object)
      end
    end

    alias :<< :push
    alias :enq :push

    # Returns a list of objects in the queue.  This method is *not* available
    # on the stdlib Queue.
    def slice start, length
      if length == 1
        synchronize do
          decode @redis.lindex @name, start
        end
      else
        synchronize do
          Array(@redis.lrange(@name, start, start + length - 1)).map do |item|
            decode item
          end
        end
      end
    end

    # Pop an item off the queue.  This method will block until an item is
    # available.
    #
    # Pass +true+ for a non-blocking pop.  If nothing is read on a non-blocking
    # pop, a ThreadError is raised.
    def pop non_block = false
      if non_block
        synchronize do
          value = @redis.lpop(@name)
          raise ThreadError unless value
          decode value
        end
      else
        synchronize do
          value = @redis.blpop(@name, 1) until value
          decode value.last
        end
      end
    end

    # Get the length of the queue
    def length
      @redis.llen @name
    end
    alias :size :length

    # Is the queue empty?
    def empty?
      size == 0
    end

    # Deletes this Queue from redis. This method is *not* available on the
    # stdlib Queue.
    def destroy
      @redis.del @name
    end

    private
    def encode object
      @coder.dump object
    end

    def decode object
      @coder.load object
    end
  end
end
