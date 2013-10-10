module Resque
  # The Failure module provides an interface for working with different
  # failure backends.
  #
  # You can use it to query the failure backend without knowing which specific
  # backend is being used. For instance, the Resque web app uses it to display
  # stats and other information.
  module Failure
    @backend = nil

    # Creates a new failure, which is delegated to the appropriate backend.
    # @param options (see Resque::Failure::Base#initialize)
    def self.create(options = {})
      backend.new(*options.values_at(:exception, :worker, :queue, :payload)).save
    end

    #
    # Sets the current backend. Expects a class descendant of
    # `Resque::Failure::Base`.
    #
    # Example use:
    #   require 'resque/failure/hoptoad'
    #   Resque::Failure.backend = Resque::Failure::Hoptoad
    # @param backend [Resque::Backend]
    # @return [void]
    def self.backend=(backend)
      @backend = backend
    end

    # Returns the current backend class. If none has been set, falls
    # back to `Resque::Failure::Redis`
    # @return [Resque::Failure::Base]
    def self.backend
      @backend ||= begin
        require 'resque/failure/redis'
        Failure::Redis
      end
    end

    # Obtain the failure queue name for a given job queue
    # @param job_queue_name [#to_s]
    # @return [String]
    def self.failure_queue_name(job_queue_name)
      name = "#{job_queue_name}_failed"
      Resque.backend.store.sadd(:failed_queues, name)
      name
    end

    # Obtain the job queue name for a given failure queue
    # @param failure_queue_name [String]
    # @return [String]
    def self.job_queue_name(failure_queue_name)
      failure_queue_name.sub(/_failed$/, '')
    end

    # Returns an array of all the failed queues in the system
    # @return (see Resque::Failure::Base::queues)
    def self.queues
      backend.queues
    end

    # Returns the int count of how many failures we have seen.
    # @param queue (see Resque::Failure::Base::count)
    # @param class_name (see Resque::Failure::Base::count)
    # @return (see Resque::Failure::Base::count)
    def self.count(queue = nil, class_name = nil)
      backend.count(queue, class_name)
    end

    # Returns an array of all the failures, paginated.
    #
    # `offset` is the int of the first item in the page, `limit` is the
    # number of items to return.
    # @param offset (see Resque::Failure::Base::all)
    # @param limit (see Resque::Failure::Base::all)
    # @param queue (see Resque::Failure::Base::all)
    # @return (see Resque::Failure::Base::all)
    def self.all(offset = 0, limit = 1, queue = nil)
      backend.all(offset, limit, queue)
    end

    # Iterate across all failures with the given options
    # @param offset (see Resque::Failure::Base::each)
    # @param limit (see Resque::Failure::Base::each) (Resque::Failure::count)
    # @param queue (see Resque::Failure::Base::each)
    # @return (see Resque::Failure::Base::each)
    # @yieldparam (see Resque::Failure::Base::each)
    # @yieldreturn (see Resque::Failure::Base::each)
    def self.each(offset = 0, limit = self.count, queue = nil, class_name = nil, &block)
      backend.each(offset, limit, queue, class_name, &block)
    end

    # The string url of the backend's web interface, if any.
    # @return (see Resque::Failure::Base::url)
    def self.url
      backend.url
    end

    # Clear all failure jobs
    # @param queue (see Resque::Failure::Base::clear)
    # @return (see Resque::Failure::Base::clear)
    def self.clear(queue = nil)
      backend.clear(queue)
    end

    # Requeue an item by its index
    # @param id (see Resque::Failure::Base::requeue)
    # @return (see Resque::Failure::Base::requeue)
    def self.requeue(id)
      backend.requeue(id)
    end

    # Requeue an item by its index and remove it
    # @param id (see Resque::Failure::Base::requeue)
    # @return (see Resque::Failure::Base::remove)
    def self.requeue_and_remove(id)
      backend.requeue(id)
      backend.remove(id)
    end

    # Requeue an item by its index to a specific queue
    # @param id (see Resque::Failure::Base::requeue_to)
    # @param queue_name (see Resque::Failure::Base::requeue_to)
    # @return (see Resque::Failure::Base::requeue_to)
    def self.requeue_to(id, queue_name)
      backend.requeue_to(id, queue_name)
    end

    # Remove an item by its index
    # @param id (see Resque::Failure::Base::remove)
    # @return (see Resque::Failure::Base::remove)
    def self.remove(id)
      backend.remove(id)
    end

    # Requeues all failed jobs in a specific queue.
    # @param queue [String] (see Resque::Failure::Base#requeue_queue)
    # @return (see Resque::Failure::Base::requeue_queue)
    def self.requeue_queue(queue)
      backend.requeue_queue(queue)
    end

    # Removes all failed jobs in a specific queue.
    # @param queue [String] (see Resque::Failure::Base#remove_queue)
    # @return (see Resque::Failure::Base::remove_queue)
    def self.remove_queue(queue)
      backend.remove_queue(queue)
    end
  end
end
