require "resque/core_ext/hash"

module Resque
  class Config
    attr_reader :redis

    # Accepts:
    #   1. A 'hostname:port' String
    #   2. A 'hostname:port:db' String (to select the Redis db)
    #   3. A 'hostname:port/namespace' String (to set the Redis namespace)
    #   4. A Redis URL String 'redis://host:port'
    #   5. An instance of `Redis`, `Redis::Backend`, `Redis::DistRedis`,
    #      or `Redis::Namespace`.

    def redis=(server)
      return if server == "" or server.nil?
      
      @redis = Backend.connect(server)
    end

    def redis_id
      if redis.respond_to?(:nodes) # distributed
        redis.nodes.map(&:id).join(', ')
      else
        redis.client.id
      end
    end
  end
end
