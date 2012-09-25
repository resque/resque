require 'resque/coder'
require 'json'

module Resque
  class JsonCoder < Coder
    def encode(object)
      if JSON.respond_to?(:dump) && JSON.respond_to?(:load)
        JSON.dump object
      else
        JSON.encode object
      end
    end

    def decode(object)
      return unless object

      begin
        if JSON.respond_to?(:dump) && JSON.respond_to?(:load)
          JSON.load object
        else
          JSON.decode object
        end
      rescue JSON::ParserError => e
        raise DecodeException, e.message, e.backtrace
      end
    end
  end
end
