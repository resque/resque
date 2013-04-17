##
# Resque::Client is a wrapper around all things Redis.
#
# This provides a level of indirection so that the rest of our code
# doesn't need to know anything about Redis, and allows us to someday
# maybe even move away from Redis to another backend if we need to.
#
# Also helps because we can mock this out in our tests. Only mock
# stuff you own.
#
# Also, we can theoretically have multiple Redis/Resques going on
# one project.
module Resque
  class Client
    attr_reader :backend, :logger

    def initialize(backend, logger)
      @backend = backend
      @logger = logger
    end
    
    # Reconnect to Redis to avoid sharing a connection with the parent,
    # retry up to 3 times with increasing delay before giving up.
    def reconnect
      tries = 0
      begin
        backend.client.reconnect
      rescue Redis::BaseConnectionError
        tries += 1

        if tries == 3
          logger.info "Error reconnecting to Redis; quitting"
          raise
        end

        logger.info "Error reconnecting to Redis; retrying"
        sleep(tries)
        retry
      end
    end
  end
end
