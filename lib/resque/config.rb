require "resque/core_ext/hash"

module Resque
  class Config
    attr_accessor :options

    def initialize(options = {})
      @options = options
    end
  end
end
