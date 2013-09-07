require 'resque/failure/each'
require 'set'

module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class RedisMultiQueue < Base
      extend Each

      # @overload (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def save
        data = {
          :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => exception.to_s,
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Resque.encode(data)
        Resque.backend.store.rpush(Resque::Failure.failure_queue_name(queue), data)
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
          [Resque.list_range(Array(queue).first, offset, limit)].flatten
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

      # @param id (see Resque::Failure::Base::requeue)
      # @param queue [#to_s]
      # @return (see Resque::Failure::Base::requeue)
      def self.requeue(id, queue = :failed)
        item = slice(id, 1, queue).first
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Resque.backend.store.lset(queue, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      # @param id (see Resque::Failure::Base::remove)
      # @param queue [#to_s]
      # @return [void]
      def self.remove(id, queue = :failed)
        sentinel = ""
        Resque.backend.store.lset(queue, id, sentinel)
        Resque.backend.store.lrem(queue, 1,  sentinel)
      end

      # Requeue all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.requeue_queue(queue)
        failure_queue = Resque::Failure.failure_queue_name(queue)
        each(0, count(failure_queue), failure_queue) { |id, _| requeue(id, failure_queue) }
      end

      # Remove all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.remove_queue(queue)
        Resque.backend.store.del(Resque::Failure.failure_queue_name(queue))
      end

      # Filter a backtrace, stripping everything above 'lib/resque/job.rb'
      # @param backtrace [Array<String>]
      # @return [Array<String>]
      def filter_backtrace(backtrace)
        backtrace.take_while { |item| !item.include?('/lib/resque/job.rb') }
      end

      private

      # Utility method used by ::all.
      # Finds failures for the given queue(s)
      # @api private
      def self.find_by_queue(queue)
        if queue.is_a? Array
          queue.each_with_object({}) do |queue, hash|
            hash[queue] = Resque.full_list queue
          end
        else
          Resque.full_list queue
        end
      end
    end
  end
end
