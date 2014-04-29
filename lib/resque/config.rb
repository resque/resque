require 'resque/core_ext/hash'

module Resque
  # A container for configuration parameters
  class Config
    attr_accessor :redis

    # @param options [Hash<Symbol,Object>]
    # @option options [Redis::Namespace,Redis::Distributed] :redis
    def initialize(options = {})
      options.each do |key, value|
        public_send("#{key}=", value)
      end
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
