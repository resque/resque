require 'multi_json'

# OkJson won't work because it doesn't serialize symbols
# in the same way yajl and json do.
if MultiJson.respond_to?(:adapter)
  raise "Please install the yajl-ruby or json gem" if MultiJson.adapter.to_s == 'MultiJson::Adapters::OkJson'
elsif MultiJson.respond_to?(:engine)
  raise "Please install the yajl-ruby or json gem" if MultiJson.engine.to_s == 'MultiJson::Engines::OkJson'
end

module Resque
  # Methods used by various classes in Resque.
  module Helpers
    class DecodeException < StandardError; end

    # Direct access to the Redis instance.
    def redis
      # No infinite recursions, please.
      # Some external libraries depend on Resque::Helpers being mixed into
      # Resque, but this method causes recursions. If we have a super method,
      # assume it is canonical. (see #1150)
      return super if defined?(super)

      Resque.redis
    end

    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    def encode(object)
      Resque.encode(object)
    end

    # Given a string, returns a Ruby object.
    def decode(object)
      Resque.decode(object)
    end

    # Given a word with dashes, returns a camel cased version of it.
    def classify(dashed_word)
      Resque.classify(dashed_word)
    end

    # Tries to find a constant with the name specified in the argument string
    def constantize(camel_cased_word)
      Resque.constantize(camel_cased_word)
    end
  end
end
