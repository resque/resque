module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class RedisMultiQueue < Base
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
        Resque.redis.rpush(failure_queue_name(queue), data)
      end

      def self.count(queue = nil)
        if queue
          Resque.redis.llen(queue).to_i
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
        Array(Resque.redis.smembers(:failed_queues))
      end

      def self.each(offset = 0, limit = self.count, queue = :failed)
        items = all(offset, limit, queue)
        items = [items] unless items.is_a? Array
        items.each_with_index do |item, i|
          yield offset + i, item
        end
      end

      def self.clear
        Resque.redis.del(:failed)
      end

      def self.requeue(id)
        item = all(id)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Resque.redis.lset(:failed, id, Resque.encode(item))
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
      end

      def self.remove(id)
        id = rand(0xffffff)
        Resque.redis.lset(:failed, id, id)
        Resque.redis.lrem(:failed, 1, id)
      end

      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/resque/job.rb') }
        backtrace.first(index.to_i)
      end

      # Obtain the queue name for a given payload
      def failure_queue_name(queue_name)
        name = "#{queue_name}_failed"
        Resque.redis.sadd(:failed_queues, name)
        name
      end
    end
  end
end
