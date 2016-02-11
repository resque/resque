module Resque
  # Raised whenever we need a queue but none is provided.
  class NoQueueError < RuntimeError; end

  # Raised when trying to create a job without a class
  class NoClassError < RuntimeError; end

  # Raised when a worker was killed while processing a job.
  class DirtyExit < RuntimeError; end

  # Raised when child process is TERM'd so job can rescue this to do shutdown work.
  class TermException < SignalException; end

  # Raised when a job is killed purposefully such that the job should not be retried.
  class DontRetryTermException < TermException; end

end
