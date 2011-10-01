module Resque
  module Views
    class Error < Layout
      def error
        "Can't connect to Redis! (#{Resque.redis_id})"
      end
    end
  end
end