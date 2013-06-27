module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
      def save
        data = {
          :failed_at => UTF8Util.clean(Time.now.strftime("%Y/%m/%d %H:%M:%S %Z")),
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
        check_queue(queue)

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
        check_queue(queue)
        Resque.list_range(:failed, offset, limit)
      end

      def self.each(offset = 0, limit = self.count, queue = :failed, class_name = nil, order = 'desc')
        all_items = Array(all(offset, limit, queue))
        reversed = false
        if order.eql? 'desc'
          all_items.reverse!
          reversed = true
        end
        all_items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name)
            if reversed
              id = (all_items.length - 1) - (offset + i)
            else
              id = offset + i
            end
            yield id, item
          end
        end
      end

      def self.clear(queue = nil)
        check_queue(queue)
        Resque.redis.del(:failed)
      end

      def self.requeue(id)
        item = all(id)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Resque.redis.lset(:failed, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
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

      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
      end

      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/resque/job.rb') }
        backtrace.first(index.to_i)
      end
    end
  end
end
