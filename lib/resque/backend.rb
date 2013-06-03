require 'redis-namespace'
require 'redis/distributed'

##
# Resque::Backend is a wrapper around all things Redis.
#
# This provides a level of indirection so that the rest of our code
# doesn't need to know anything about Redis, and allows us to someday
# maybe even move away from Redis to another data store if we need to.
#
# Also helps because we can mock this out in our tests. Only mock
# stuff you own.
#
# Also, we can theoretically have multiple Redis/Resques going on
# one project.
module Resque
  class Backend

    # This error is thrown if we have a problem connecting to
    # the back end.
    ConnectionError = Class.new(StandardError)

    attr_reader :store, :logger

    def initialize(store, logger)
      @store = store
      @logger = logger
    end

    def self.connect(server)
      case server
      when String
        if server['redis://']
          redis = connect_to(server)
        else
          redis, namespace = parse_redis_url(server)
        end
        Redis::Namespace.new(namespace || :resque, :redis => redis)
      when Redis::Namespace, Redis::Distributed
        server
      when Redis
        Redis::Namespace.new(:resque, :redis => server)
      else
        raise ArgumentError, "Invalid Server: #{server.inspect}"
      end
    end

    def self.connect_to(server)
      Redis.connect(:url => server, :thread_safe => true)
    end

    def self.parse_redis_url(server)
      server, namespace = server.split('/', 2)
      host, port, db = server.split(':')

      redis = Redis.new(
        :host => host,
        :port => port,
        :db => db,
        :thread_safe => true
      )

      [redis, namespace]
    end

    # Reconnects to the store
    #
    # Maybe your store died, maybe you've just forked. Whatever the
    # reason, this method will attempt to reconnect to the store.
    #
    # If it can't reconnect, it will attempt to retry the connection after
    # sleeping, throwing an exception if exceeding MAX_RECONNECT_ATTEMPTS.
    MAX_RECONNECT_ATTEMPTS = 3
    def reconnect
      store.client.reconnect
    rescue Redis::BaseConnectionError
      tries ||= 0
      if (tries += 1) < MAX_RECONNECT_ATTEMPTS
        logger.info "Error reconnecting to Redis; retrying"
        sleep(tries)
        retry
      else
        logger.info "Error reconnecting to Redis; quitting"
        raise ConnectionError
      end
    end
  end
end
