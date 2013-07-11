module Resque
  # An exception raised when the coder can't encode
  class EncodeException < StandardError; end

  # An exception raised when the coder can't decode
  class DecodeException < StandardError; end

  # A wrapper around any coder.
  # @see {Resque::JsonCoder} for reference implementation
  # @abstract - subclass and implement #encode and #decode,
  #             ensuring that EncodeException and DecodeException
  #             are raised when encoding or decoding is exceptional.
  class Coder
    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    # @param object [Object]
    # @return [String]
    # @raise [EncodeException] if input could not be encoded
    def encode(object)
      raise EncodeException
    end

    # alias for encode
    # @param object [Object] (see #encode)
    # @return [String] (see #encode)
    # @raise [EncodeException] (see #encode)
    def dump(object)
      encode(object)
    end

    # Given a string, returns a Ruby object.
    # @param object [String]
    # @return [Object]
    # @raise [DecodeException] if input could not be decoded
    def decode(object)
      raise DecodeException
    end

    # alias for decode
    # @param object [String] (see #decode)
    # @return [Object] (see #decode)
    # @raise [DecodeException] (see #decode)
    def load(object)
      decode(object)
    end
  end
end
