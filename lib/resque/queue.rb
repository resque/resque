require 'redis'
require 'redis-namespace'
require 'thread'
require 'mutex_m'

module Resque
  class Queue
    include Mutex_m

    VERSION = '1.0.0'

    def initialize name, redis, coder = Marshal
      super()
      @name  = "queue:#{name}"
      @redis = redis
      @coder = coder
    end

    def push object
      synchronize do
        @redis.rpush @name, encode(object)
      end
    end

    alias :<< :push
    alias :enq :push

    def pop non_block = false
      if non_block
        synchronize do
          value = @redis.rpop(@name)
          raise ThreadError unless value
          decode value
        end
      else
        synchronize do
          value = @redis.brpop(@name, 1) until value
          decode value.last
        end
      end
    end

    def length
      @redis.llen @name
    end
    alias :size :length

    def empty?
      size == 0
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
