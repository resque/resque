module Resque
  module Failure
    def self.create(options = {})
      backend.new(*options.values_at(:exception, :worker, :queue, :payload)).save
    end

    ##
    # require 'resque/failure/hoptoad'
    # Resque::Failure.backend = Resque::Failure::Hoptoad
    def self.backend=(backend)
      @backend = backend
    end

    def self.backend
      return @backend if @backend
      require 'resque/failure/redis'
      @backend = Failure::Redis
    end

    def self.count
      backend.count
    end

    def self.all(start = 0, count = 1)
      backend.all(start, count)
    end

    def self.url
      backend.url
    end
  end
end
