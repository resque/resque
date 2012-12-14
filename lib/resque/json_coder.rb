require 'resque/coder'
require 'json'

module Resque
  class JsonCoder < Coder
    def encode(object)
      begin
        JSON.dump object
      rescue Encoding::UndefinedConversionError => e
        raise EncodeException, e.message, e.backtrace
      end
    end

    def decode(object)
      return unless object

      begin
        JSON.load object
      rescue JSON::ParserError => e
        raise DecodeException, e.message, e.backtrace
      end
    end
  end
end
