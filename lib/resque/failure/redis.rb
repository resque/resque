require 'time'
require 'resque/failure/each'

module Resque
  class Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
      extend Each

      # @overload (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @raise (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def self.save(failure)
        encoded_data = Resque.encode failure.data
        id = failure.redis_id
        Resque.backend.store.pipelined do
          Resque.backend.store.hset :failed, id, encoded_data
          Resque.backend.store.zadd :failed_ids, id, id
        end
      end

      # @overload find(id)
      #   Find the failure object with the given id
      #   @param id [#to_s] The id of the record to retrieve
      #   @return [Resque::Failure]
      # @overload find(id, id, ...)
      #   Find the failure objects with the given ids
      #   @param ids [#to_s] A list of ids for the records to retrieve
      #   @return [Array<Resque::Failure>]
      def self.find(*ids)
        results = Resque::Failure.hash_find(*ids, :failed)
        ids.size > 1 ? results : results.first
      end

      # @overload (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @raise (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.count(queue = nil, class_name = nil)
        check_queue(queue)

        if class_name
          all(:class_name => class_name).size
        else
          Resque.backend.store.hlen(:failed).to_i
        end
      end

      # @overload (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @raise (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.queues
        [:failed]
      end

      # @overload all(opts = {})
      #   Get all failures, filtered by options
      #
      #   The only queue that is checked in the Redis store is the :failed queue
      #
      #   @example
      #     Resque::Failure::Redis.all
      #     #=> [{}, {}, ...]
      #
      #     Resque::Failure::Redis.all(:class_name => ['Foo', 'Bar'], :offset => 10, :limit => 5)
      #     #=> [{}, {}, ...]
      #
      #   @param [Hash] opts The options to filter the failures by. When omitted, returns all failures in the :failed queue.
      #   @option opts [String, Array<String>] :class_name - the name of the class(es) to filter by
      #   @option opts [Integer] :offset - the number of failures to offset the results by (ex. pagination)
      #   @option opts [Integer] :limit - the maximum number of failures returned (ex. pagination)
      #   @return [Array<Resque::Failure>]
      def self.all(opts = {})
        failures = if opts[:offset] || opts[:limit]
          slice_from_options opts
        else
          Resque::Failure.full_hash(:failed)
        end

        if opts[:class_name]
          failures = filter_by_class_name_from failures, opts[:class_name]
        end

        failures
      end

      # Returns a paginated array of failure objects.
      # @param offset [Integer] The index to begin retrieving records from the Redis list
      # @param limit [Integer] The maximum number of records to return
      # @param queue [#to_s] The queue to retrieve records from
      # @return [Array<Resque::Failure>]
      def self.slice(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        ids = Resque::Failure.list_ids_range :failed_ids, offset, limit
        Array(find *ids)
      end

      # Clear all failures objects from the :failed queue
      # @param (see Resque::Failure::Base::clear)
      # @return (see Resque::Failure::Base::clear)
      def self.clear(queue = nil)
        check_queue(queue)
        Resque.backend.store.pipelined do
          Resque.backend.store.del :failed
          Resque.backend.store.del :failed_ids
        end
      end

      # Requeue failure(s) with the given id(s)
      # @param ids (see Resque::Failure::Base::requeue)
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(*ids)
        failures = find *ids
        Array(failures).map &:retry
      end


      # Requeue failure(s) with the given id(s) on the specified queue
      # @param ids (see Resque::Failure::Base::requeue_to)
      # @param queue_name (see Resque::Failure::Base::requeue_to)
      # @return (see Resque::Failure::Base::requeue_to)
      def self.requeue_to(*ids, queue_name)
        failures = find *ids
        Array(failures).map { |failure| failure.retry queue_name }
      end

      # Remove failure(s) with the given id(s)
      # @param ids (see Resque::Failure::Base::remove)
      # @return (see Resque::Failure::Base::remove)
      def self.remove(*ids)
        Resque.backend.store.pipelined do
          ids.each do |id|
            Resque.backend.store.zrem :failed_ids, id
            Resque.backend.store.hdel :failed, id
          end
        end
      end

      # Requeue all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.requeue_queue(queue)
        all.each do |failure|
          failure.retry if failure.queue == queue
        end
      end

      # Remove all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.remove_queue(queue)
        all.each do |failure|
          failure.destroy if failure.queue == queue
        end
      end

      # Ensures that the given queue is either nil or its to_s returns 'failed'
      # @param queue [nil,String]
      # @raise [ArgumentError] unless queue is nil or 'failed'
      # @return [void]
      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
      end
    end
  end
end
