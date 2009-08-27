module Resque
  module Stat
    extend self

    def get(stat)
      redis.get("stat:#{stat}").to_i
    end

    def [](stat)
      get(stat)
    end

    def incr(stat, by = 1)
      redis.incr("stat:#{stat}", by)
    end

    def decr(stat, by = 1)
      redis.decr("stat:#{stat}", by)
    end

    def clear(stat)
      redis.del("stat:#{stat}")
    end

    def redis
      Resque.redis
    end
  end
end
