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
        data = Yajl::Encoder.encode(data)
        Resque.redis.rpush(:failed, data)
      end
    end
  end
end
