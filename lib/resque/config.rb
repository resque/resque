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

      @redis = case server
      when String
        if server['redis://']
          redis = Redis.connect(:url => server, :thread_safe => true)
        else
          server, namespace = server.split('/', 2)
          host, port, db = server.split(':')

          redis = Redis.new(
            :host => host,
            :port => port,
            :db => db,
            :thread_safe => true
          )
        end
        Redis::Namespace.new(namespace || :resque, :redis => redis)
      when Redis::Namespace, Redis::Distributed
        server
      when Redis
        Redis::Namespace.new(:resque, :redis => server)
      end
    end

    def redis_id
      # support 1.x versions of redis-rb
      if redis.respond_to?(:server)
        redis.server
      elsif redis.respond_to?(:nodes) # distributed
        redis.nodes.map(&:id).join(', ')
      else
        redis.client.id
      end
    end
  end
end
