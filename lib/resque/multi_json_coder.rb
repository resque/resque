require 'multi_json'
require 'resque/coder'

# OkJson won't work because it doesn't serialize symbols
# in the same way yajl and json do.
if MultiJson.engine.to_s == 'MultiJson::Engines::OkJson'
  raise "Please install the yajl-ruby or json gem"
end

module Resque
  class MultiJsonCoder < Coder
    def encode(object)
      ::MultiJson.dump(object)
    end

    def decode(object)
      return unless object

      begin
        ::MultiJson.load(object)
      rescue ::MultiJson::DecodeError => e
        raise DecodeException, e.message, e.backtrace
      end
    end
  end
end
