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
    def redis
      Resque.redis
    end
    alias :data_store :redis

    # Returns the int value of a stat, given a string stat name.
    def get(stat)
      data_store.stat(stat)
    end

    # Alias of `get`
    def [](stat)
      get(stat)
    end

    # For a string stat name, increments the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # incremented by that amount.
    def incr(stat, by = 1)
      data_store.increment_stat(stat,by)
    end

    # Increments a stat by one.
    def <<(stat)
      incr stat
    end

    # For a string stat name, decrements the stat by one.
    #
    # Can optionally accept a second int parameter. The stat is then
    # decremented by that amount.
    def decr(stat, by = 1)
      data_store.decremet_stat(stat,by)
    end

    # Decrements a stat by one.
    def >>(stat)
      decr stat
    end

    # Removes a stat from Redis, effectively setting it to 0.
    def clear(stat)
      data_store.clear_stat(stat)
    end
  end
end
