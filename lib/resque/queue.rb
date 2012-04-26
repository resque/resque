require 'redis'
require 'redis-namespace'
require 'thread'
require 'mutex_m'

module Resque
  ###
  # Exception raised when trying to access a queue that's already destroyed
  class QueueDestroyed < RuntimeError; end

  ###
  # A queue interface that quacks like Queue from Ruby's stdlib.
  class Queue
    include Mutex_m

    attr_reader :name, :redis_name

    ###
    # Create a new Queue object with +name+ on +redis+ connection, and using
    # the +coder+ for encoding and decoding objects that are stored in redis.
    def initialize name, redis = Resque.redis, coder = Marshal
      super()
      @name       = name
      @redis_name = "queue:#{@name}"
      @redis      = redis
      @coder      = coder
      @destroyed  = false

      @redis.sadd(:queues, @name)
    end

    # Add +object+ to the queue
    # If trying to push to an already destroyed queue, it will raise a Resque::QueueDestroyed exception
    def push object
      raise QueueDestroyed if destroyed?

      synchronize do
        @redis.rpush @redis_name, encode(object)
      end
    end

    alias :<< :push
    alias :enq :push

    # Returns a list of objects in the queue.  This method is *not* available
    # on the stdlib Queue.
    def slice start, length
      if length == 1
        synchronize do
          decode @redis.lindex @redis_name, start
        end
      else
        synchronize do
          Array(@redis.lrange(@redis_name, start, start + length - 1)).map do |item|
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
          value = @redis.lpop(@redis_name)
          raise ThreadError unless value
          decode value
        end
      else
        synchronize do
          value = @redis.blpop(@redis_name, 1) until value
          decode value.last
        end
      end
    end

    # Get the length of the queue
    def length
      @redis.llen @redis_name
    end
    alias :size :length

    # Is the queue empty?
    def empty?
      size == 0
    end

    # Deletes this Queue from redis. This method is *not* available on the
    # stdlib Queue.
    #
    # If there are multiple queue objects of the same name, Queue A and Queue
    # B and you delete Queue A, pushing to Queue B will have unknown side
    # effects. Queue A will be marked destroyed, but Queue B will not.
    def destroy
      @redis.del @redis_name
      @redis.srem(:queues, @name)
      @destroyed = true
    end

    # returns +true+ if the queue is destroyed and +false+ if it isn't
    def destroyed?
      @destroyed
    end

    def encode object
      @coder.dump object
    end

    def decode object
      @coder.load object
    end
  end
end
