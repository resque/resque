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
        encoded_data = Resque.encode(failure.data)
        Resque.backend.store.rpush(:failed, encoded_data)
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
          Resque.backend.store.llen(:failed).to_i
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
      #   The main finder method for failure objects.
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
      #   @return [Array<Hash>]
      def self.all(opts = {})
        failures = if opts[:offset] || opts[:limit]
          slice_from_options opts
        else
          Resque::Failure.full_list(:failed)
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
      # @return [Array<Hash{String=>Object}>]
      def self.slice(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        [Resque::Failure.list_range(:failed, offset, limit)].flatten
      end

      # @overload (see Resque::Failure::Base::clear)
      # @param (see Resque::Failure::Base::clear)
      # @return (see Resque::Failure::Base::clear)
      def self.clear(queue = nil)
        check_queue(queue)
        Resque.backend.store.del(:failed)
      end

      # @overload (see Resque::Failure::Base::requeue)
      # @param (see Resque::Failure::Base::requeue)
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(id, queue = :failed)
        item = slice(id).first
        item.retry if item
      end

      # @param id [Integer] index of item to requeue
      # @param queue_name [#to_s]
      # @return [void]
      def self.requeue_to(id, queue_name)
        item = slice(id).first
        item.retry queue_name if item
      end

      # @overload (see Resque::Failure::Base::remove)
      # @param (see Resque::Failure::Base::remove)
      # @return (see Resque::Failure::Base::remove)
      def self.remove(index, queue = :failed)
        sentinel = ""
        Resque.backend.store.lset(:failed, index, sentinel)
        Resque.backend.store.lrem(:failed, 1,  sentinel)
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
        # removal is a two step process because deletion is currently based on
        # an index position, so first we clear the entry in the Redis list,
        # then we delete all cleared entries with ::sweep_cleared_failures
        all.each do |failure|
          failure.clear if failure.queue == queue
        end
        sweep_cleared_failures
      end

      # Ensures that the given queue is either nil or its to_s returns 'failed'
      # @param queue [nil,String]
      # @raise [ArgumentError] unless queue is nil or 'failed'
      # @return [void]
      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
      end

      private

      def self.sweep_cleared_failures
        sentinel = ''
        Resque.backend.store.lrem(:failed, 0, sentinel)
      end
    end
  end
end
