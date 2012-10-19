module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
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
        Resque.redis.rpush(:failed, data)
      end

      def self.count
        Resque.redis.llen(:failed).to_i
      end

      def self.all(offset = 0, limit = 1)
        Resque.list_range(:failed, offset, limit)
      end

      def self.each(offset = 0, limit = self.count)
        Array(all(offset, limit)).each_with_index do |item, i|
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
    end
  end
end
