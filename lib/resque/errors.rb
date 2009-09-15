module Resque
  # Raised whenever we need a queue but none is provided.
  class NoQueueError < RuntimeError; end
end
