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
    def initialize name, pool = Resque.pool, coder = Marshal
      super()
      @name       = name
      @redis_name = "queue:#{@name}"
      @pool       = pool
      @coder      = coder
      @destroyed  = false

      @pool.with_connection do |conn|
        conn.sadd(:queues, @name)
      end
    end

    # Add +object+ to the queue
    # If trying to push to an already destroyed queue, it will raise a Resque::QueueDestroyed exception
    def push object
      raise QueueDestroyed if destroyed?

      @pool.with_connection do |conn|
        conn.rpush @redis_name, synchronize {encode(object) }
      end
    end

    alias :<< :push
    alias :enq :push

    # Returns a list of objects in the queue.  This method is *not* available
    # on the stdlib Queue.
    def slice start, length
      if length == 1
        synchronize do
          decode(@pool.with_connection {|conn| conn.lindex(@redis_name , start) })
        end
      else
        Array(
          @pool.with_connection do |conn|
            conn.lrange(@redis_name, start, start + length - 1)
          end
        ).map do |item|
          synchronize {decode item }
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
        value = @pool.with_connection {|pool| pool.lpop(@redis_name) }
        raise ThreadError unless value
        synchronize {decode value }
      else
        value = @pool.with_connection {|pool| pool.blpop(@redis_name, 1) } until value
        synchronize {decode value.last }
      end
    end

    # Retrieves data from the queue head, and removes it.
    #
    # Blocks for +timeout+ seconds if the queue is empty, and returns nil if
    # the timeout expires.
    def poll(timeout)
      queue_name, payload = @pool.with_connection {|pool| pool.blpop(@redis_name, timeout) }
      return unless payload

      synchronize do
        [self, decode(payload)]
      end
    end

    # Get the length of the queue
    def length
      @pool.with_connection {|pool| pool.llen @redis_name }
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
      @pool.with_connection do |conn|
        conn.del @redis_name
        conn.srem(:queues, @name)
      end
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
