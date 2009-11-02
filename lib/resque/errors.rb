module Resque
  # Raised whenever we need a queue but none is provided.
  class NoQueueError < RuntimeError; end

  # Raised when trying to create a job without a class
  class NoClassError < RuntimeError; end
end
