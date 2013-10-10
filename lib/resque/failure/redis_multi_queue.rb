require 'resque/failure/each'

module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class RedisMultiQueue < Base
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
            n = 0
            each(0, count(queue), queue, class_name) { n += 1 }
            n
          else
            Resque.backend.store.llen(queue).to_i
          end
        else
          total = 0
          queues.each { |q| total += count(q) }
          total
        end
      end

      # @overload all( offset = 0, limit = 1, queue = :failed)
      # @param offset (see Resque::Failure::Base::all)
      # @param limit (see Resque::Failure::Base::all)
      # @param queue [#to_s] (:failed)
      # @return (see Resque::Failure::Base::all)
      def self.all(offset = 0, limit = 1, queue = :failed)
        [Resque.list_range(queue, offset, limit)].flatten
      end

      # @overload (see Resque::Failure::Base::queues)
      # @param (see Resque::Failure::Base::queues)
      # @return (see Resque::Failure::Base::queues)
      def self.queues
        Array(Resque.backend.store.smembers(:failed_queues))
      end

      extend Each

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
        item = all(id, 1, queue).first
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
    end
  end
end
