module Resque
  module Failure
    class Redis < Base
      def save
        data = {
          :failed_at => Time.now.to_s,
          :payload   => payload,
          :error     => exception.to_s,
          :backtrace => exception.backtrace,
          :worker    => worker,
          :queue     => queue
        }
        data = Resque.encode(data)
        Resque.redis.rpush(:failed, data)
      end

      def self.count
        Resque.redis.llen(:failed).to_i
      end

      def self.all(start = 0, count = 1)
        Resque.list_range(:failed, start, count)
      end
    end
  end
end
