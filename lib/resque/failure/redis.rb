module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
    @marker = '__delete__'

      def save
        data = {
          :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S"),
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => exception.to_s,
          :backtrace => Array(exception.backtrace),
          :worker    => worker.to_s,
          :queue     => queue
        }
        data = Resque.encode(data)
        Resque.redis.rpush(:failed, data)
      end

      def self.count
        Resque.redis.llen(:failed).to_i
      end

      def self.archived_count
        Resque.redis.llen(:archived).to_i
      end

      def self.all(start = 0, count = 1)
        purge
        Resque.list_range(:failed, start, count)
      end

      def self.archived(start = 0, count = 1)
        Resque.list_range(:archived, start, count)
      end

      def self.clear
        Resque.redis.del(:failed)
      end

      def self.forget
        Resque.redis.del(:archived)
      end

      def self.purge
        Resque.redis.lrem(:failed, count, @marker)
      end

      def self.requeue(index)
        item = all(index)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Job.create(item['queue'], item['payload']['class'], *item['payload']['args'])
        Resque.redis.rpush(:archived, Resque.encode(item))
        Resque.redis.lset(:failed, index, @marker)
        purge
        Stat.incr(:archived)
      end
    end
  end
end
