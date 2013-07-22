module Resque
  # The Failure module provides an interface for working with different
  # failure backends.
  #
  # You can use it to query the failure backend without knowing which specific
  # backend is being used. For instance, the Resque web app uses it to display
  # stats and other information.
  module Failure
    # Creates a new failure, which is delegated to the appropriate backend.
    #
    # Expects a hash with the following keys:
    #   :exception - The Exception object
    #   :worker    - The Worker object who is reporting the failure
    #   :queue     - The string name of the queue from which the job was pulled
    #   :payload   - The job's payload
    def self.create(options = {})
      backend.new(*options.values_at(:exception, :worker, :queue, :payload)).save
    end

    #
    # Sets the current backend. Expects a class descendent of
    # `Resque::Failure::Base`.
    #
    # Example use:
    #   require 'resque/failure/airbrake'
    #   Resque::Failure.backend = Resque::Failure::Airbrake
    def self.backend=(backend)
      @backend = backend
    end

    # Returns the current backend class. If none has been set, falls
    # back to `Resque::Failure::Redis`
    def self.backend
      return @backend if @backend

      case ENV['FAILURE_BACKEND']
      when 'redis_multi_queue'
        require 'resque/failure/redis_multi_queue'
        @backend = Failure::RedisMultiQueue
      when 'redis', nil
        require 'resque/failure/redis'
        @backend = Failure::Redis
      else
        raise ArgumentError, "invalid failure backend: #{FAILURE_BACKEND}"
      end
    end

    # Obtain the failure queue name for a given job queue
    def self.failure_queue_name(job_queue_name)
      name = "#{job_queue_name}_failed"
      Resque.redis.sadd(:failed_queues, name)
      name
    end

    # Obtain the job queue name for a given failure queue
    def self.job_queue_name(failure_queue_name)
      failure_queue_name.sub(/_failed$/, '')
    end

    # Returns an array of all the failed queues in the system
    def self.queues
      backend.queues
    end

    # Returns the int count of how many failures we have seen.
    def self.count(queue = nil, class_name = nil)
      backend.count(queue, class_name)
    end

    # Returns an array of all the failures, paginated.
    #
    # `offset` is the int of the first item in the page, `limit` is the
    # number of items to return.
    def self.all(offset = 0, limit = 1, queue = nil)
      backend.all(offset, limit, queue)
    end

    # Iterate across all failures with the given options
    def self.each(offset = 0, limit = self.count, queue = nil, class_name = nil, order = 'desc', &block)
      backend.each(offset, limit, queue, class_name, order, &block)
    end

    # The string url of the backend's web interface, if any.
    def self.url
      backend.url
    end

    # Clear all failure jobs
    def self.clear(queue = nil)
      backend.clear(queue)
    end

    def self.requeue(id)
      backend.requeue(id)
    end

    def self.remove(id)
      backend.remove(id)
    end
    
    # Requeues all failed jobs in a specific queue.
    # Queue name should be a string.
    def self.requeue_queue(queue)
      backend.requeue_queue(queue)
    end

    # Removes all failed jobs in a specific queue.
    # Queue name should be a string.
    def self.remove_queue(queue)
      backend.remove_queue(queue)
    end
  end
end
