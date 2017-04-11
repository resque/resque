module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class RedisMultiQueue < Base

      def data_store
        Resque.data_store
      end

      def self.data_store
        Resque.data_store
      end

      def save
        data = {
          :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => UTF8Util.clean(exception.to_s),
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Resque.encode(data)
        data_store.push_to_failed_queue(data,Resque::Failure.failure_queue_name(queue))
      end

      def self.count(queue = nil, class_name = nil)
        if queue
          if class_name
            n = 0
            each(0, count(queue), queue, class_name) { n += 1 }
            n
          else
            data_store.num_failed(queue).to_i
          end
        else
          total = 0
          queues.each { |q| total += count(q) }
          total
        end
      end

      def self.all(offset = 0, limit = 1, queue = :failed)
        Resque.list_range(queue, offset, limit)
      end

      def self.queues
        data_store.failed_queue_names(:failed_queues)
      end

      def self.each(offset = 0, limit = self.count, queue = :failed, class_name = nil, order = 'desc')
        items = all(offset, limit, queue)
        items = [items] unless items.is_a? Array
        reversed = false
        if order.eql? 'desc'
          items.reverse!
          reversed = true
        end
        items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name)
            id = reversed ? (items.length - 1) - (offset + i) : offset + i
            yield id, item
          end
        end
      end

      def self.clear(queue = :failed)
        queues = queue ? Array(queue) : self.queues
        queues.each { |queue| data_store.clear_failed_queue(queue) }
      end

      def self.requeue(id, queue = :failed)
        item = all(id, 1, queue)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        data_store.update_item_in_failed_queue(id,Resque.encode(item),queue)
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(id, queue = :failed)
        data_store.remove_from_failed_queue(id,queue)
      end

      def self.requeue_queue(queue)
        failure_queue = Resque::Failure.failure_queue_name(queue)
        each(0, count(failure_queue), failure_queue) { |id, _| requeue(id, failure_queue) }
      end

      def self.requeue_all
        queues.each { |queue| requeue_queue(Resque::Failure.job_queue_name(queue)) }
      end

      def self.remove_queue(queue)
        data_store.remove_failed_queue(Resque::Failure.failure_queue_name(queue))
      end

      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/resque/job.rb') }
        backtrace.first(index.to_i)
      end
    end
  end
end
