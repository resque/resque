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
        Resque.redis.rpush(:failed, data)
      end

      def self.count(queue = nil, class_name = nil)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"

        if class_name
          n = 0
          each(0, count(queue), queue, class_name) { n += 1 } 
          n
        else
          Resque.redis.llen(:failed).to_i
        end
      end

      def self.queues
        [:failed]
      end

      def self.all(offset = 0, limit = 1, queue = nil)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s == "failed"
        Resque.list_range(:failed, offset, limit)
      end

      include Each

      def self.clear(queue = nil)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s == "failed"
        Resque.redis.del(:failed)
      end

      def self.requeue(id)
        item = all(id)
        item['retried_at'] = Time.now.rfc2822
        Resque.redis.lset(:failed, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.requeue_to(id, queue_name)
        item = all(id)
        item['retried_at'] = Time.now.rfc2822
        Resque.redis.lset(:failed, id, Resque.encode(item))
        Job.create(queue_name, item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(id)
        sentinel = ""
        Resque.redis.lset(:failed, id, sentinel)
        Resque.redis.lrem(:failed, 1,  sentinel)
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

      def filter_backtrace(backtrace)
        backtrace.take_while { |item| !item.include?('/lib/resque/job.rb') }
      end
    end
  end
end
