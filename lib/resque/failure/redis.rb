require 'time'
require 'resque/failure/each'

module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
      # @overload (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @raise (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def save
        data = {
          :failed_at => Time.now.rfc2822,
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => exception.to_s,
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Resque.encode(data)
        Resque.backend.store.rpush(:failed, data)
      end

      # @overload (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @raise (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.count(queue = nil, class_name = nil)
        check_queue(queue)

        if class_name
          n = 0
          each(0, count(queue), queue, class_name) { n += 1 }
          n
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

      # @overload (see Resque::Failure::Base::all)
      # @param (see Resque::Failure::Base::all)
      # @return (see Resque::Failure::Base::all)
      def self.all(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        [Resque.list_range(:failed, offset, limit)].flatten
      end

      extend Each

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
      def self.requeue(id)
        item = all(id).first
        item['retried_at'] = Time.now.rfc2822
        Resque.backend.store.lset(:failed, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      # @param id [Integer] index of item to requeue
      # @param queue_name [#to_s]
      # @return [void]
      def self.requeue_to(id, queue_name)
        item = all(id).first
        item['retried_at'] = Time.now.rfc2822
        Resque.backend.store.lset(:failed, id, Resque.encode(item))
        Job.create(queue_name, item['payload']['class'], *item['payload']['args'])
      end

      # @overload (see Resque::Failure::Base::remove)
      # @param (see Resque::Failure::Base::remove)
      # @return (see Resque::Failure::Base::remove)
      def self.remove(id)
        sentinel = ""
        Resque.backend.store.lset(:failed, id, sentinel)
        Resque.backend.store.lrem(:failed, 1,  sentinel)
      end

      # Requeue all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.requeue_queue(queue)
        i = 0
        while job = all(i).first
           requeue(i) if job['queue'] == queue
           i += 1
        end
      end

      # Remove all items from failed queue where their original queue was
      # the given string
      # @param queue [String]
      # @return [void]
      def self.remove_queue(queue)
        i = 0
        while job = all(i).first
          if job['queue'] == queue
            # This will remove the failure from the array so do not increment the index.
            remove(i)
          else
            i += 1
          end
        end
      end

      # Ensures that the given queue is either nil or its to_s returns 'failed'
      # @param queue [nil,String]
      # @raise [ArgumentError] unless queue is nil or 'failed'
      # @return [void]
      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
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
