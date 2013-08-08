require 'resque/coder'
require 'json'

module Resque
  # The default coder for JSON serialization
  class JsonCoder < Coder

    # Different exceptions in different environments.
    # This wrapper attempts to mitigate that.
    module MultiEncodeExceptionWrapper
      def self.===(exception)
        if defined?(EncodingError)
          return true if EncodingError === exception
        end
        JSON::GeneratorError === exception
      end
    end

    # @param object (see Resque::Coder#encode)
    # @raise (see Resque::Coder#encode)
    # @return (see Resque::Coder#encode)
    def encode(object)
      JSON.dump object
    rescue MultiEncodeExceptionWrapper => e
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
