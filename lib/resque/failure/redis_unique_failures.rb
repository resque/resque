# frozen_string_literal: true

require 'resque/failure/redis'

module Resque
  module Failure
    class RedisUniqueFailures < Redis
      def save
        super unless failure_already_exists?
      end

      private

      def failure_already_exists?
        self.class.each(0, self.class.count, :failed) do |_, item|
          if item['exception'] == exception.class.to_s && item['payload'] == payload
            return true
          end
        end
        false
      end
    end
  end
end
