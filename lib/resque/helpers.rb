module Resque
  # Methods used by various classes in Resque.
  module Helpers
    # Direct access to the Redis instance.
    def redis
      Resque.redis
    end

    #
    # encoding / decoding
    #

    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    def encode(object)
      if defined? Yajl
        Yajl::Encoder.encode(object)
      else
        JSON(object)
      end
    end

    # Given a string, returns a Ruby object.
    def decode(object)
      return unless object

      if defined? Yajl
        Yajl::Parser.parse(object)
      else
        JSON(object)
      end
    end
  end
end
