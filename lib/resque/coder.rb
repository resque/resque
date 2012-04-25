module Resque
  class EncodeException < StandardError; end
  class DecodeException < StandardError; end

  class Coder
    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    def encode(object)
      raise EncodeException
    end

    # alias for encode
    def dump(object)
      encode(object)
    end

    # Given a string, returns a Ruby object.
    def decode(object)
      raise DecodeException
    end

    # alias for decode
    def load(object)
      decode(object)
    end
  end
end
