require 'multi_json'
require 'resque/coder'

# OkJson won't work because it doesn't serialize symbols
# in the same way yajl and json do.
engine = MultiJson.respond_to?(:adapter) ? MultiJson.adapter : MultiJson.engine
if engine.to_s == 'MultiJson::Engines::OkJson' || engine.to_s == 'MultiJson::Adapters::OkJson'
  raise "Please install the yajl-ruby or json gem"
end

module Resque
  class MultiJsonCoder < Coder
    def encode(object)
      ::MultiJson.respond_to?(:dump) ? ::MultiJson.dump(object) : ::MultiJson.encode(object)
    end

    def decode(object)
      return unless object

      begin
        ::MultiJson.respond_to?(:load) ? ::MultiJson.load(object) : ::MultiJson.decode(object)
      rescue ::MultiJson::DecodeError => e
        raise DecodeException, e.message, e.backtrace
      end
    end
  end
end
