require "resque/core_ext/hash"

module Resque
  class Config
    def initialize(options = {})
      options.each do |key, value|
        public_send("#{key}=", value)
      end
    end
    attr_accessor :redis

    def redis_id
      if redis.respond_to?(:nodes) # distributed
        redis.nodes.map(&:id).join(', ')
      else
        redis.client.id
      end
    end
  end
end
