require 'thread'

module Resque
  ###
  # Sized LIFO queue.
  class SizedStack < SizedQueue
    def initialize(size)
      super
      class << @que
        alias :shift :pop
      end
    end
  end
end
