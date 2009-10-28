module Resque
  module Helpers
    def redis
      Resque.redis
    end

    #
    # encoding / decoding
    #

    def encode(object)
      if defined? Yajl
        Yajl::Encoder.encode(object)
      else
        JSON(object)
      end
    end

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
