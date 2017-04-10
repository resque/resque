module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base

      def data_store
        Resque.data_store
      end

      def self.data_store
        Resque.data_store
      end

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
        data_store.push_to_failed_queue(data)
      end

      def self.count(queue = nil, class_name = nil)
        check_queue(queue)

        if class_name
          n = 0
          each(0, count(queue), queue, class_name) { n += 1 } 
          n
        else
          data_store.num_failed
        end
      end

      def self.queues
        data_store.failed_queue_names
      end

      def self.all(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        Resque.list_range(:failed, offset, limit)
      end

      def self.each(offset = 0, limit = self.count, queue = :failed, class_name = nil, order = 'desc')
        if class_name
          original_limit = limit
          limit = count
        end
        all_items = limit == 1 ? [all(offset,limit,queue)] : Array(all(offset, limit, queue))
        reversed = false
        if order.eql? 'desc'
          all_items.reverse!
          reversed = true
        end
        all_items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name && (original_limit -= 1) >= 0)
            if reversed
              id = (all_items.length - 1) + (offset - i)
            else
              id = offset + i
            end
            yield id, item
          end
        end
      end

      def self.clear(queue = nil)
        check_queue(queue)
        data_store.clear_failed_queue
      end

      def self.requeue(id, queue = nil)
        check_queue(queue)
        item = all(id)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        data_store.update_item_in_failed_queue(id,Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(id, queue = nil)
        check_queue(queue)
        data_store.remove_from_failed_queue(id, queue)
      end

      def self.requeue_queue(queue)
        i = 0
        while job = all(i)
           requeue(i) if job['queue'] == queue
           i += 1
        end
      end

      def self.requeue_all
        count.times do |num|
          requeue(num)
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
