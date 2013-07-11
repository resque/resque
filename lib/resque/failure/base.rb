module Resque
  module Failure
    # All Failure classes are expected to subclass Base.
    #
    # When a job fails, a new instance of your Failure backend is created
    # and #save is called.
    # @abstract
    class Base
      # The exception object raised by the failed job
      attr_accessor :exception

      # The worker object who detected the failure
      attr_accessor :worker

      # The string name of the queue from which the failed job was pulled
      attr_accessor :queue

      # The payload object associated with the failed job
      attr_accessor :payload

      # @option options [Exception]           :exception - The Exception object
      # @option options [Resque::Worker]      :worker    - The Worker object who is
      #                                                    reporting the failure
      # @option options [String]              :queue     - The string name of the queue
      #                                                    from which the job was pulled
      # @option options [Hash<String,Object>] :payload   - The job's payload
      def initialize(exception, worker, queue, payload)
        @exception = exception
        @worker    = worker
        @queue     = queue
        @payload   = payload
      end

      # When a job fails, a new instance of your Failure backend is created
      # and #save is called.
      #
      # This is where you POST or PUT or whatever to your Failure service.
      # @return [void]
      def save
      end

      # The number of failures.
      # @param queue [#to_s] (nil) if provided, use specified queue
      #                            instead of :failed
      # @param class_name [String] (nil) if provided, limit to jobs with
      #                                  the provided class_name
      # @return [Integer]
      def self.count(queue = nil, class_name = nil)
        0
      end

      # Returns an array of all available failure queues
      # @return [Array<#to_s>]
      def self.queues
        []
      end

      # Returns a paginated array of failure objects.
      # @return (see Resque::list_range)
      def self.all(offset = 0, limit = 1)
        []
      end

      # Iterate across failed objects
      # @overload (see Resque::Failure::Each#each)
      def self.each(*args)
      end

      # A URL where someone can go to view failures.
      # @return [String] if backend supports web interface
      # @return [nil] if backend does not support a web interface
      def self.url
      end

      # Clear all failure objects
      # @overload clear(queue = nil)
      #   @param queue [#to_s]
      def self.clear(*args)
      end

      # @overload self.requeue(index)
      # @param index [Integer]
      def self.requeue(index)
      end

      # @overload self.remove(index)
      # @param index [Integer]
      def self.remove(index)
      end
    end
  end
end
