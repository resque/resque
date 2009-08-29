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
      @backend || Redis
    end
  end
end
