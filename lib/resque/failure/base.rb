module Resque
  class Failure
    # All Failure classes are expected to subclass Base.
    #
    # When a job fails, a new Resque::Failure instance is created and handed to
    # the ::save method for your backend
    # @abstract
    class Base
      # This is where you POST or PUT or whatever to your Failure service.
      # @param failure [Resque::Failure] The Failure instance wrapping the failed job
      # @return [void]
      def self.save(failure)
        raise NotImplementedError, '::save must be implemented in subclasses of Resque::Failure::Base'
      end

      # @overload find(id, [:queue => :foo_failed])
      #   Find the failure object with the given id (optionally limited by queue)
      #   @param id [#to_s] The id of the record to retrieve
      #   @param opts [Hash] An optional hash to specify the name of the :queue to restrict the find to
      #   @return [Resque::Failure]
      #   @example Find a single failure across all failure queues
      #     Resque::Failure.find 1
      #   @example Find a single failure on a specific failure queue
      #     Resque::Failure.find 1, :queue => :foo_failed
      # @overload find(id, id, ..., [:queue => :foo_failed])
      #   Find the failure objects with the given ids (optionally limited by queue)
      #   @param ids [#to_s] A list of ids for the records to retrieve
      #   @param opts [Hash] An optional hash to specify the name of the :queue to restrict the find to
      #   @return [Array<Resque::Failure>]
      #   @example Find multiple failures across all failure queues
      #     Resque::Failure.find 1, 2, 3
      #   @example Find multiple failures on a specific failure queue
      #     Resque::Failure.find 1, 2, 3, :queue => :foo_failed
      def self.find(*args)
        raise NotImplementedError, '::find must be implemented in subclasses of Resque::Failure::Base'
      end

      # The number of failures.
      # @param queue [#to_s] (nil) if provided, use specified queue
      #                            instead of :failed
      # @param class_name [String] (nil) if provided, limit to jobs with
      #                                  the provided class_name
      # @return [Integer]
      def self.count(queue = nil, class_name = nil)
        raise NotImplementedError, '::count must be implemented in subclasses of Resque::Failure::Base'
      end

      # Returns an array of all available failure queues
      # @return [Array<#to_s>]
      def self.queues
        raise NotImplementedError, '::queues must be implemented in subclasses of Resque::Failure::Base'
      end

      # Returns an array of all failure objects.
      # @param [Hash] opts The options to filter the failures by. When omitted, returns all failures across all failure queues.
      # @option opts [String, Symbol, Array<String, Symbol>] :queue - the name(s) of the queue(s) to filter by
      # @option opts [String, Array<String>] :class_name - the name of the class(es) to filter by
      # @option opts [Integer] :offset - the number of failures to offset the results by (ex. pagination)
      # @option opts [Integer] :limit - the maximum number of failures returned (ex. pagination)
      # @return [Array<Resque::Failure>, Hash{Symbol=>Array<Resque::Failure>}]
      def self.all(opts = {})
        raise NotImplementedError, '::all must be implemented in subclasses of Resque::Failure::Base'
      end

      # Returns a paginated array of failure objects.
      # @param offset [Integer] The index to begin retrieving records from the Redis list
      # @param limit [Integer] The maximum number of records to return
      # @param queue [#to_s] The queue to retrieve records from
      # @return (see Resque::list_range)
      def self.slice(offset = 0, limit = 1, queue = nil)
        raise NotImplementedError, '::slice must be implemented in subclasses of Resque::Failure::Base'
      end

      # A URL where someone can go to view failures.
      # @return [String] if backend supports web interface
      # @return [nil] if backend does not support a web interface
      def self.url
        raise NotImplementedError, '::url must be implemented in subclasses of Resque::Failure::Base'
      end

      # Clear all failure objects from the given queue
      # @param queue [#to_s] Name of queue to clear
      def self.clear(queue = nil)
        raise NotImplementedError, '::clear must be implemented in subclasses of Resque::Failure::Base'
      end

      # @overload requeue(id, [:queue => :foo_failed])
      #   Requeue the job for the failure object with the given id (optionally limited by queue)
      #   @param id [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @return [Resque::Job] The job that was created from the #retry
      # @overload requeue(id, id, ..., [:queue => :foo_failed])
      #   Requeue the jobs for the failure objects with the given ids (optionally limited by queue)
      #   @param ids [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @return [Array<Resque::Job>] The jobs created from #retry
      def self.requeue(*args)
        raise NotImplementedError, '::requeue must be implemented in subclasses of Resque::Failure::Base'
      end

      # @overload requeue_to(id, [:queue => :foo_failed], queue_name)
      #   Requeue the job for the failure object with the given id (optionally limited by queue) to the given queue
      #   @param id [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @param queue_name [#to_s] The name of the queue to push the job to
      #   @return [Resque::Job] The job that was created from the #retry
      # @overload requeue_to(id, id, ..., [:queue => :foo_failed], queue_name)
      #   Requeue the jobs for the failure objects with the given ids (optionally limited by queue) to the given queue name
      #   @param ids [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @param queue_name [#to_s] The name of the queue to push the jobs to
      #   @return [Array<Resque::Job>] The jobs created from #retry
      def self.requeue_to(*args, queue_name)
        raise NotImplementedError, '::requeue_to must be implemented in subclasses of Resque::Failure::Base'
      end

      # @overload remove(id, [:queue => :foo_failed])
      #   Remove the failure object with the given id (optionally limited by queue)
      #   @param id [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @return [void]
      # @overload remove(id, id, ..., [:queue => :foo_failed])
      #   Remove the failure objects with the given ids (optionally limited by queue)
      #   @param ids [#to_s] (see Resque::Failure::Base::find)
      #   @param opts [#to_s] (see Resque::Failure::Base::find)
      #   @return [void]
      def self.remove(*args)
        raise NotImplementedError, '::remove must be implemented in subclasses of Resque::Failure::Base'
      end

      private

      # Utility method used by ::all.
      # Filters the given set of failures by class name(s).
      # @api private
      def self.filter_by_class_name_from(collection, class_name)
        class_names = Set.new Array(class_name)
        case collection
        when Array
          collection.select do |failure|
            class_names.include?(failure.class_name)
          end
        when Hash
          collection.each_with_object({}) do |(queue, failures), hash|
            hash[queue] = filter_by_class_name_from(failures, class_name)
          end
        else
          raise TypeError, "expected Array or Hash, #{collection.class} given."
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
