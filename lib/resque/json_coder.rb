require 'resque/coder'
require 'json'

module Resque
  # Sweet jruby --1.8 hax.
  if defined?(Encoding)
    ENCODING_EXCEPTION = Encoding::UndefinedConversionError
  else
    ENCODING_EXCEPTION = JSON::GeneratorError
  end

  class JsonCoder < Coder
    def encode(object)
      begin
        JSON.dump object
      rescue ENCODING_EXCEPTION => e
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
