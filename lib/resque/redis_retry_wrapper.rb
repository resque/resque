# a wrapper for redis that allows us to do things like retry commands that fail because of connection errors
module Resque
  class RedisRetryWrapper

    def initialize(redis)
      @redis = redis
    end

    def method_missing(m, *args, &block)
      # send all method calls directly to redis instance, but retry on connection errors
      retryable(:tries => tries, :sleep => sleep_seconds, :on => [TimeoutError, Errno::EAGAIN]) do
        @redis.send(m, *args, &block)
      end
    end
    
    def tries
      3
    end
    
    def sleep_seconds
      1
    end

  end
end
