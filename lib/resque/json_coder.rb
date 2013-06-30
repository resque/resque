require 'resque/coder'
require 'json'

module Resque
  # Sweet jruby --1.8 hax.
  if defined?(Encoding)
    ENCODING_EXCEPTION = Encoding::UndefinedConversionError
  else
    ENCODING_EXCEPTION = JSON::GeneratorError
  end

  # The default coder for JSON serialization
  class JsonCoder < Coder
    # @param object (see Resque::Coder#encode)
    # @raise (see Resque::Coder#encode)
    # @return (see Resque::Coder#encode)
    def encode(object)
      JSON.dump object
    rescue ENCODING_EXCEPTION => e
      raise EncodeException, e.message, e.backtrace
    end

    # @param object (see Resque::Coder#decode)
    # @raise (see Resque::Coder#decode)
    # @return (see Resque::Coder#decode)
    def decode(object)
      return unless object
      JSON.load object
    rescue JSON::ParserError => e
      raise DecodeException, e.message, e.backtrace
    end
  end
end
