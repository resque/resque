module Resque
  # Raised whenever we need a queue but none is provided.
  class NoQueueError < RuntimeError; end

  # Raised when trying to create a job without a class
  class NoClassError < RuntimeError; end

  # Raised when a worker was killed while processing a job.
  class DirtyExit < RuntimeError
    attr_reader :process_status

    def initialize(message=nil, process_status=nil)
      @process_status = process_status
      super message
    end
  end

  class PruneDeadWorkerDirtyExit < DirtyExit
    def initialize(hostname, job)
      job ||= "<Unknown Job>"
      super("Worker #{hostname} did not gracefully exit while processing #{job}")
    end
  end

  # Raised when child process is TERM'd so job can rescue this to do shutdown work.
  class TermException < SignalException; end
end
