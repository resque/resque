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

  class EagerLoadConfigurationError < StandardError
    def initialize
      super(with_message)
    end

    private

    def with_message
      <<~MSG
        Eager load for environments is not configured correctly.
        You need to specify a block with boolean values set for each
        of your project environments. For example:
        
          Resque.rails_eager_load_configure do |environment|
            environment.development = false
            environment.staging = true
            environment.production = true
          end
      MSG
    end
  end
end
