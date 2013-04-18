require 'time'
require 'resque/failure/each'

module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
      def save
        data = {
          :failed_at => Time.now.rfc2822,
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => UTF8Util.clean(exception.to_s),
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Resque.encode(data)
        Resque.backend.store.rpush(:failed, data)
      end

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

      def self.queues
        [:failed]
      end

      def self.all(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        Resque.list_range(:failed, offset, limit)
      end

      include Each

      def self.clear(queue = nil)
        check_queue(queue)
        Resque.backend.store.del(:failed)
      end

      def self.requeue(id)
        item = all(id)
        item['retried_at'] = Time.now.rfc2822
        Resque.backend.store.lset(:failed, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.requeue_to(id, queue_name)
        item = all(id)
        item['retried_at'] = Time.now.rfc2822
        Resque.backend.store.lset(:failed, id, Resque.encode(item))
        Job.create(queue_name, item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(id)
        sentinel = ""
        Resque.backend.store.lset(:failed, id, sentinel)
        Resque.backend.store.lrem(:failed, 1,  sentinel)
      end

      def self.requeue_queue(queue)
        i = 0
        while job = all(i)
           requeue(i) if job['queue'] == queue
           i += 1
        end
      end

      def self.remove_queue(queue)
        i = 0
        while job = all(i)
          if job['queue'] == queue
            # This will remove the failure from the array so do not increment the index.
            remove(i)
          else
            i += 1
          end
        end
      end

      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
      end

      def filter_backtrace(backtrace)
        backtrace.take_while { |item| !item.include?('/lib/resque/job.rb') }
      end
    end
  end
end
