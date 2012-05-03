require 'resque/coder'

module Resque
  class MarshalCoder < Coder
    def encode(object)
      Marshal.dump(object)
    end

    def decode(object)
      Marshal.load(object)
    rescue TypeError => e
      raise DecodeException, e.message, e.backtrace
    end
  end
end
