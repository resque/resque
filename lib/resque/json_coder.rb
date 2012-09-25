require 'resque/coder'
require 'json'

module Resque
  class JsonCoder < Coder
    def encode(object)
      JSON.dump(object)
    end

    def decode(object)
      if object
        begin
          JSON.load(object)
        rescue JSON::ParserError => e
          raise DecodeException, e.message, e.backtrace
        end
      end
    end
  end
end
