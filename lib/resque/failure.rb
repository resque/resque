module Resque
  # The Failure module provides an interface for working with different
  # failure backends.
  #
  # You can use it to query the failure backend without knowing which specific
  # backend is being used. For instance, the Resque web app uses it to display
  # stats and other information.
  class Failure
    @backend = nil

    # @return [String] The name of the worker object who detected the failure
    attr_reader :worker

    # @return [String] The name of the queue from which the failed job was pulled
    attr_reader :queue

    # @return [Hash] The payload object associated with the failed job
    attr_reader :payload

    # @return [String] The time when the failure was last retried
    attr_reader :retried_at

    # @return [Integer] The unique id of the failure in Redis
    attr_reader :redis_id

    # @param options [Hash] The options hash used to instantiate a failure
    # @option options [Exception]           :raw_exception - The Exception object
    # @option options [Resque::Worker]      :worker        - The Worker object who is reporting the failure
    # @option options [String]              :queue         - The string name of the queue from which the job was pulled
    # @option options [Hash<String,Object>] :payload       - The job's payload
    def initialize(options = {})
      options.each do |attribute, value|
        send("#{attribute}=", value)
      end
    end

    # Creates a new failure, which is delegated to the appropriate backend.
    # @param (see Resque::Failure#initialize)
    def self.create(options)
      failure = new(options.merge(:redis_id => next_failure_id))
      failure.save

      failure
    end

    # Returns an integer from a Redis counter to be used as the failure id
    # @return [Integer] The id to be assigned to the failure
    def self.next_failure_id
      Resque.backend.store.incr :next_failure_id
    end

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
      "#{job_queue_name}_failed"
    end

    # Obtain the failure ids queue name for a given failure queue
    # @param failure_queue_name [#to_s]
    # @return [String]
    def self.failure_ids_queue_name(failure_queue_name)
      "#{failure_queue_name}_ids"
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

    # Returns all failure objects filtered by options
    # @param opts (see Resque::Failure::Base::all)
    # @return (see Resque::Failure::Base::all)
    def self.all(opts = {})
      backend.all(opts)
    end

    # Find the failure objects with the given args
    # @param args (see Resque::Failure::Base::find)
    # @return (see Resque::Failure::Base::find)
    def self.find(*args)
      backend.find(*args)
    end

    # Returns an array of all the failures, paginated.
    #
    # `offset` is the int of the first item in the page, `limit` is the
    # number of items to return.
    # @param offset (see Resque::Failure::Base::slice)
    # @param limit (see Resque::Failure::Base::slice)
    # @param queue (see Resque::Failure::Base::slice)
    # @return (see Resque::Failure::Base::slice)
    def self.slice(offset = 0, limit = 1, queue = nil)
      backend.slice(offset, limit, queue)
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

    # Requeue an item by its id
    # @param ids (see Resque::Failure::Base::requeue)
    # @return (see Resque::Failure::Base::requeue)
    def self.requeue(*ids)
      backend.requeue(*ids)
    end

    # Requeue an item by its id and remove it
    # @param ids (see Resque::Failure::Base::requeue)
    # @return (see Resque::Failure::Base::remove)
    def self.requeue_and_remove(*ids)
      backend.requeue(*ids)
      backend.remove(*ids)
    end

    # Requeue an item by its id to a specific job queue
    # @param ids (see Resque::Failure::Base::requeue_to)
    # @param queue_name (see Resque::Failure::Base::requeue_to)
    # @return (see Resque::Failure::Base::requeue_to)
    def self.requeue_to(*ids, queue_name)
      backend.requeue_to(*ids, queue_name)
    end

    # Remove an item by its id
    # @param ids (see Resque::Failure::Base::remove)
    # @return (see Resque::Failure::Base::remove)
    def self.remove(*ids)
      backend.remove(*ids)
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

    # Retrieves a list of failure ids from the given key. This command (and the
    # underlying list structure) is used to simplify slicing/pagination. Failure
    # objects are stored in unordered Redis hashes, so slicing would always
    # incur the cost of sorting.
    # @param key [#to_s] The name of the Redis list of failure ids
    # @param start [Integer] The zero-based index to start from
    # @param count [Integer] The maximum number of ids to retrieve
    # @return [Array<String>] List of failure ids
    def self.list_ids_range(key, start = 0, count = 1)
      Resque.backend.store.lrange key, start, start+count-1
    end

    # Delegates to Resque::hash_find to retrieve records from Redis, then
    # instantiates each result as a Failure instance
    # @param ids [#to_s] (see Resque::hash_find)
    # @param queue [#to_s] (see Resque::hash_find)
    # @return [Array<Resque::Failure>]
    def self.hash_find(*ids, queue)
      Resque.hash_find *ids, queue do |item|
        failure_for item, queue
      end
    end

    # Delegates to Resque::full_hash to retrieve records from Redis, then
    # instantiates each result as a Failure instance
    # @param queue [#to_s] (see Resque::full_hash)
    # @return [Array<Resque::Failure>]
    def self.full_hash(queue)
      Resque.full_hash queue do |item|
        failure_for item, queue
      end
    end

    # Saves the failure instance (delegates to the appropriate backend)
    # @return (see Resque::Failure::Base::save)
    def save
      self.class.backend.save(self)
    end

    # The hash contents to store for a Failure instance in Redis
    # @return [Hash]
    def data
      {
        :failed_at  => failed_at,
        :payload    => payload,
        :exception  => exception,
        :error      => error,
        :backtrace  => backtrace,
        :worker     => worker.to_s,
        :queue      => queue,
        :retried_at => retried_at,
        :redis_id   => redis_id
      }
    end

    # The time when the job failed
    # @return [String]
    def failed_at
      @failed_at ||= formatted_now
    end

    # The name of the exception class raised by the failed job
    # @return [String]
    def exception
      @exception ||= raw_exception.class.to_s
    end

    # The contents of the exception raised by the failed job
    # @return [String]
    def error
      @error ||= raw_exception.to_s
    end

    # The filtered exception backtrace
    # @return [String]
    def backtrace
      @backtrace ||= Array(raw_exception.backtrace).take_while do |item|
        !item.include?('/lib/resque/job.rb')
      end
    end

    # The name of the Redis failure queue this failure was pushed to
    # @return [#to_s]
    def failed_queue
      @failed_queue ||= self.class.failure_queue_name queue
    end

    # The name of the sorted Redis list of failure ids
    # @return [String]
    def failed_id_queue
      @failed_id_queue ||= self.class.failure_ids_queue_name failed_queue
    end

    # Convenience method for accessing the class name from the payload
    # @return [String]
    def class_name
      payload && payload['class']
    end

    # Convenience method for accessing the args array from the payload
    # @return [Array]
    def args
      payload && payload['args']
    end

    # Touches the retried_at time for the failure and tries to process the job
    # again within the given queue (defaults to the same queue the job failed
    # in initially)
    # @param queue_name [#to_s] Name of queue to retry job in
    # @return (see Resque::Job::create)
    def retry(queue_name = queue)
      self.retried_at = formatted_now
      Resque.backend.store.hset failed_queue, redis_id, Resque.encode(data)
      Job.create(queue_name, class_name, *args)
    end

    # Deletes the Failure record in Redis and freezes the instance
    # @return [Resque::Failure] frozen Failure instance
    def destroy
      self.class.remove redis_id
      freeze
    end

    private

    # The actual exception object gets lost in the round trip to Redis, (it's
    # converted into String parts stored in #exception and #error).
    # @return [Exception] The exception object raised by the failed job
    # @api private
    attr_accessor :raw_exception

    # The name of the Redis failure queue this failure was pushed to
    # @api private
    attr_writer :failed_queue

    # The name of the Redis failure queue this failure was pushed to
    # @api private
    attr_writer :failed_at

    # The name of the exception class raised by the failed job
    # @api private
    attr_writer :exception

    # The contents of the exception raised by the failed job
    # @api private
    attr_writer :error

    # The filtered exception backtrace
    # @api private
    attr_writer :backtrace

    # @return [String] The name of the worker object who detected the failure
    # @api private
    attr_writer :worker

    # @return [String] The name of the queue from which the failed job was pulled
    # @api private
    attr_writer :queue

    # @return [Hash] The payload object associated with the failed job
    # @api private
    attr_writer :payload

    # @return [String] The time when the failure was last retried
    # @api private
    attr_writer :retried_at

    # @return [Integer] The unique id of the failure in Redis
    attr_writer :redis_id

    # Time format helper method
    # @return [String]
    # @api private
    def formatted_now
      Time.now.strftime("%Y/%m/%d %H:%M:%S")
    end

    # Instantiates new failure instances with raw Redis query results
    # @return [Resque::Failure]
    # @api private
    def self.failure_for(item, failed_queue)
      if item
        Resque::Failure.new item.merge(
          :failed_queue => failed_queue
        )
      end
    end
  end
end
