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

      # Returns an array of all failure objects.
      # @param [Hash] opts The options to filter the failures by. When omitted, returns all failures across all failure queues.
      # @option opts [String, Symbol, Array<String, Symbol>] :queue - the name(s) of the queue(s) to filter by
      # @option opts [String, Array<String>] :class_name - the name of the class(es) to filter by
      # @option opts [Integer] :offset - the number of failures to offset the results by (ex. pagination)
      # @option opts [Integer] :limit - the maximum number of failures returned (ex. pagination)
      # @return [Array<Hash>, Hash{Symbol=>Array<Hash>}]
      def self.all(opts = {})
        []
      end

      # Returns a paginated array of failure objects.
      # @param offset [Integer] The index to begin retrieving records from the Redis list
      # @param limit [Integer] The maximum number of records to return
      # @param queue [#to_s] The queue to retrieve records from
      # @return (see Resque::list_range)
      def self.slice(offset = 0, limit = 1, queue = nil)
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

      private

      # Utility method used by ::all.
      # Filters the given set of failures by class name(s).
      # @api private
      def self.filter_by_class_name_from(collection, class_name)
        class_names = Set.new Array(class_name)
        if collection.is_a? Array
          collection.select! do |failures|
            failures['payload'] && class_names.include?(failures['payload']['class'])
          end
        else
          collection.each do |queue, failures|
            filter_by_class_name_from(failures, class_name)
          end
        end
      end

      # Utility method used by ::all.
      # Calls ::slice with the provided options.
      # @api private
      def self.slice_from_options(opts)
        slice_defaults = {
          :offset => 0,
          :limit => -1,
          :queue => queues
        }
        opts = slice_defaults.merge(opts)
        slice(opts[:offset], opts[:limit], opts[:queue])
      end
    end
  end
end
