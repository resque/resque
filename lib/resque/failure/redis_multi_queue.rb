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
        encoded_data = Resque.encode failure.data
        Resque.backend.store.pipelined do
          Resque.backend.store.sadd :failed_queues, failure.failed_queue
          Resque.backend.store.hset failure.failed_queue, failure.redis_id, encoded_data
          Resque.backend.store.rpush failure.failed_id_queue, failure.redis_id
        end
      end

      # Find the failure(s) with the given id(s) (optionally limited by queue)
      # @param ids (see Resque::Failure::Base::find)
      # @param opts (see Resque::Failure::Base::find)
      # @return (see Resque::Failure::Base::find)
      def self.find(*args)
        queues = args.last.is_a?(Hash) ? Array(args.pop[:queue]) : self.queues
        ids = args
        failures = queues.each_with_object([]) do |key, ary|
          ary.concat Resque::Failure.hash_find(*ids, key).compact
          break ary if ary.size == ids.size
        end
        args.size > 1 ? failures : failures.first
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
              result.values.reduce(0) { |memo, failures| memo += failures.size }
            end
          else
            Resque.backend.store.hlen(queue).to_i
          end
        else
          queues.reduce(0) { |memo, q| memo += count(q) }
        end
      end

      # @overload all(opts = {})
      #   Get all failures, filtered by options
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
      #   @return [Array<Resque::Failure>, Hash{Symbol=>Array<Resque::Failure>}]
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
      #   @param queue [#to_s] The failure queue to slice from
      #   @return [Array<Resque::Failure>]
      # @overload slice(offset, limit, array_of_queue_names)
      #   Returns a hash with keys as queue names and values as arrays of failure objects
      #   @param offset [Integer] The index to begin retrieving records from the Redis list
      #   @param limit [Integer] The maximum number of records to return
      #   @param queue [Array<#to_s>] The failure queues to slice from
      #   @return [<Hash{Symbol=>Array<Resque::Failure>}>]
      def self.slice(offset = 0, limit = 1, queue = queues)
        if queue.is_a? Array
          queue.each_with_object({}) do |queue_name, hash|
            hash[queue_name.to_sym] = slice offset, limit, queue_name
          end
        else
          ids = Resque::Failure.list_ids_range(
            Resque::Failure.failure_ids_queue_name(queue), offset, limit)
          Array(find *ids, :queue => queue)
        end
      end

      # @overload (see Resque::Failure::Base::queues)
      # @param (see Resque::Failure::Base::queues)
      # @return (see Resque::Failure::Base::queues)
      def self.queues
        Array(Resque.backend.store.smembers(:failed_queues))
      end

      # Clear all failure objects from the given queue
      # @param (see Resque::Failure::Base::clear)
      # @return (see Resque::Failure::Base::clear)
      def self.clear(queue = :failed)
        Resque.backend.store.pipelined do
          Resque.backend.store.del queue
          Resque.backend.store.del Resque::Failure.failure_ids_queue_name(queue)
          Resque.backend.store.srem :failed_queues, queue
        end
      end

      # Requeue jobs with the given id(s)
      # @param ids (see Resque::Failure::Base::requeue)
      # @param opts (see Resque::Failure::Base::requeue)
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(*args)
        failures = find *args
        Array(failures).map &:retry
      end

      # Requeue jobs with the given id(s) on the specified queue
      # @param ids (see Resque::Failure::Base::requeue_to)
      # @param opts (see Resque::Failure::Base::requeue_to)
      # @param queue_name (see Resque::Failure::Base::requeue_to)
      # @return (see Resque::Failure::Base::requeue_to)
      def self.requeue_to(*args, queue_name)
        failures = find *args
        Array(failures).map { |failure| failure.retry queue_name }
      end

      # @param ids (see Resque::Failure::Base::remove)
      # @param opts (see Resque::Failure::Base::remove)
      # @return [void]
      def self.remove(*args)
        failures = Array(find *args)
        Resque.backend.store.pipelined do
          failures.each do |failure|
            Resque.backend.store.hdel failure.failed_queue, failure.redis_id
            Resque.backend.store.lrem failure.failed_id_queue, 1, failure.redis_id
          end
        end
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
        clear Resque::Failure.failure_queue_name(queue)
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
          Resque::Failure.full_hash queue
        end
      end
    end
  end
end
