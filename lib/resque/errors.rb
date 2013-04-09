module Resque
  # Raised whenever we need a queue but none is provided.
  class NoQueueError < RuntimeError; end

  # Raised when trying to create a job without a class
  class NoClassError < RuntimeError; end

  # Raised when a worker was killed while processing a job.
  class DirtyExit < RuntimeError; end

  # Raised when child process is TERM'd so job can rescue this to do shutdown work.
  class TermException < SignalException; end

  # Raised from a before_perform hook to abort the job.
  class DontPerform < StandardError; end
end
