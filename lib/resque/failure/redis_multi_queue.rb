require 'resque/failure/each'
require 'set'

module Resque
  class Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class RedisMultiQueue < Base
      extend Each

      # @overload (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def self.save(failure)
        encoded_data = Resque.encode(failure.data)
        Resque.backend.store.sadd(:failed_queues, failure.failed_queue)
        Resque.backend.store.rpush(failure.failed_queue, encoded_data)
      end

      # @overload (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.count(queue = nil, class_name = nil)
        if queue
          if class_name
            result = all(:queue => queue, :class_name => class_name)
            if result.is_a? Array
              result.size
            else
              result.values.reduce(0) { |memo, fails| memo += fails.size }
            end
          else
            Resque.backend.store.llen(queue).to_i
          end
        else
          queues.reduce(0) { |memo, q| memo += count(q) }
        end
      end

      # @overload all(opts = {})
      #   The main finder method for failure objects.
      #
      #   When no options are provided, it will return all failure objects across
      #   all failure queues in a hash, so be careful if you have tons of failures.
      #
      #   If given a single failure queue name as a symbol or string, it will
      #   return an array of results.
      #
      #   If given an array of queue names, it will return a hash with the queue
      #   name as the key and the failure objects in arrays.
      #
      #   @example
      #     Resque::Failure::RedisMultiQueue.all(:queue => :foo_failed)
      #     #=> [{}, {}, ...]
      #
      #     Resque::Failure::RedisMultiQueue.all(:queue => [:foo_failed, :bar_failed])
      #     #=> {:foo_failed => [{}, {}, ...], :bar_failed => [{}, {}, ...]}
      #
      #   @param [Hash] opts The options to filter the failures by. When omitted, returns all failures across all failure queues.
      #   @option opts [String, Symbol, Array<String, Symbol>] :queue - the name(s) of the queue(s) to filter by
      #   @option opts [String, Array<String>] :class_name - the name of the class(es) to filter by
      #   @option opts [Integer] :offset - the number of failures to offset the results by (ex. pagination)
      #   @option opts [Integer] :limit - the maximum number of failures returned (ex. pagination)
      #   @return [Array<Hash>, Hash{Symbol=>Array<Hash>}]
      def self.all(opts = {})
        failures = if opts[:offset] || opts[:limit]
          slice_from_options opts
        else
          find_by_queue(opts[:queue] || queues)
        end

        if opts[:class_name]
          failures = filter_by_class_name_from failures, opts[:class_name]
        end

        failures.symbolize_keys! if failures.is_a? Hash

        failures
      end

      # @overload slice(offset, limit, single_queue_name)
      #   Returns a paginated array of failure objects.
      #   @param offset [Integer] The index to begin retrieving records from the Redis list
      #   @param limit [Integer] The maximum number of records to return
      #   @param queue [#to_s] The queue to slice from
      #   @return [Array<Hash{String=>Object}>]
      # @overload slice(offset, limit, array_of_queue_names)
      #   Returns a hash with keys as queue names and values as arrays of failure objects
      #   @param offset [Integer] The index to begin retrieving records from the Redis list
      #   @param limit [Integer] The maximum number of records to return
      #   @param queue [Array<#to_s>] The queues to slice from
      #   @return [<Hash{Symbol=>Array<Hash{String=>Object}>}>]
      def self.slice(offset = 0, limit = 1, queue = queues)
        if queue.is_a? Array
          queue.each_with_object({}) do |queue_name, hash|
            hash[queue_name.to_sym] = slice offset, limit, queue_name
          end
        else
          [Resque::Failure.list_range(Array(queue).first, offset, limit)].flatten
        end
      end

      # @overload (see Resque::Failure::Base::queues)
      # @param (see Resque::Failure::Base::queues)
      # @return (see Resque::Failure::Base::queues)
      def self.queues
        Array(Resque.backend.store.smembers(:failed_queues))
      end

      # @overload (see Resque::Failure::Base::clear)
      # @param (see Resque::Failure::Base::clear)
      # @return (see Resque::Failure::Base::clear)
      def self.clear(queue = :failed)
        Resque.backend.store.del(queue)
      end

      # @param index (see Resque::Failure::Base::requeue)
      # @param queue [#to_s]
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(index, queue = :failed)
        item = slice(index, 1, queue).first
        item.retry if item
      end

      # @param index (see Resque::Failure::Base::remove)
      # @param queue [#to_s]
      # @return [void]
      def self.remove(index, queue = :failed)
        sentinel = ""
        Resque.backend.store.lset(queue, index, sentinel)
        Resque.backend.store.lrem(queue, 1, sentinel)
      end

      # Requeue all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.requeue_queue(queue)
        failure_queue = Resque::Failure.failure_queue_name(queue)
        all(:queue => failure_queue).each(&:retry)
      end

      # Remove all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.remove_queue(queue)
        Resque.backend.store.del(Resque::Failure.failure_queue_name(queue))
      end

      private

      # Utility method used by ::all.
      # Finds failures for the given queue(s)
      # @api private
      def self.find_by_queue(queue)
        if queue.is_a? Array
          queue.each_with_object({}) do |queue_name, hash|
            hash[queue_name] = find_by_queue queue_name
          end
        else
          Resque::Failure.full_list queue
        end
      end
    end
  end
end
