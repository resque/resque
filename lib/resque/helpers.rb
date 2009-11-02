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

    def classify(dashed_word)
      dashed_word.split('-').each { |part| part[0] = part[0].chr.upcase }.join
    end

    def constantize(camel_cased_word)
      camel_cased_word = camel_cased_word.to_s

      if camel_cased_word.include?('-')
        camel_cased_word = classify(camel_cased_word)
      end

      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_get(name) || constant.const_missing(name)
      end
      constant
    end
  end
end
