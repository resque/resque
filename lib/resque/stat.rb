module Resque
  # The stat subsystem. Used to keep track of integer counts.
  #
  #   Get a stat:  Stat[name]
  #   Incr a stat: Stat.incr(name)
  #   Decr a stat: Stat.decr(name)
  #   Kill a stat: Stat.clear(name)
  module Stat
    extend self

    # Direct access to the Redis instance.
    # @return [Redis::Namespace,Redis::Distributed]
    def redis
      Resque.backend.store
    end

    # Returns the int value of a stat, given a string stat name.
    # @param stat [#to_s] - stat name
    # @return [Integer]
    def get(stat)
      redis.get("stat:#{stat}").to_i
    end

    # Alias of `get`
    # @param stat (see #get)
    # @return (see #get)
    def [](stat)
      get(stat)
    end

    # For a string stat name, increments the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # incremented by that amount.
    # @param stat [#to_s] - stat name
    # @param by [Integer] (1)
    # @return [Integer] - the new value
    def incr(stat, by = 1)
      redis.incrby("stat:#{stat}", by)
    end

    # Increments a stat by one.
    # @param stat (see #incr)
    # @return (see #incr)
    def <<(stat)
      incr stat
    end

    # For a string stat name, decrements the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # decremented by that amount.
    # @param stat [#to_s] - stat name
    # @param by [Integer] (1)
    # @return [Integer] - the new value
    def decr(stat, by = 1)
      redis.decrby("stat:#{stat}", by)
    end

    # Decrements a stat by one.
    # @param stat (see #decr)
    # @return (see #decr)
    def >>(stat)
      decr stat
    end

    # Removes a stat from Redis, effectively setting it to 0.
    # @param stat [#to_s]
    # @return [void]
    def clear(stat)
      redis.del("stat:#{stat}")
    end
  end
end
