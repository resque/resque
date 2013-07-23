require "resque/core_ext/hash"

module Resque
  # A container for configuration parameters
  class Config
    attr_writer :redis
    
    # @param options [Hash<Symbol,Object>]
    # @option options [Redis::Namespace,Redis::Distributed] :redis
    def initialize(options = {})
      options.each do |key, value|
        public_send("#{key}=", value)
      end
    end

    # Returns the current redis connection, or raises
    # an exception if it doesn't exist.
    # @return [Redis::Namespace,Redis::Distributed]
    # @raise [RuntimeError] if redis is not configured.
    def redis
      @redis || raise('redis connection not configured!')
    end

    # Get the ID of the underlying redis connection
    # @return [String]
    def redis_id
      if redis.respond_to?(:nodes) # distributed
        redis.nodes.map(&:id).join(', ')
      else
        redis.client.id
      end
    end
  end
end
