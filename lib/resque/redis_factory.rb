module Resque
  class RedisFactory
    def self.from_server(server)
      case server
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
        namespace ||= :resque

        Redis::Namespace.new(namespace, :redis => redis)
      when Redis::Namespace
        server
      when Redis
        Redis::Namespace.new(:resque, :redis => server)
      else
        Redis.new
      end
    end
  end
end
