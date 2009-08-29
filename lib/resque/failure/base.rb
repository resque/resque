module Resque
  module Failure
    class Base
      attr_accessor :exception, :worker, :queue, :payload

      def initialize(exception, worker, queue, payload)
        @exception = exception
        @worker    = worker
        @queue     = queue
        @payload   = payload
      end

      # implement me in your subclass
      def save
      end

      # implement me in your subclass
      def self.count
        0
      end

      # implement me in your subclass
      def self.all(start = 0, count = 1)
        []
      end

      # return a value if the failures are stored
      def self.url
      end

      def log(message)
        @worker.log(message)
      end
    end
  end
end
