# This class handles registering/unregistering/updating worker status in Redis
module Resque
  # The registry of what a given worker is working on
  class WorkerRegistry
    # Underlying Redis prefix for workers registry
    REDIS_WORKERS_KEY = :workers
    # Underlying Redis prefix for a worker's registry
    REDIS_SINGLE_WORKER_KEY = :worker

    # Direct access to the Redis instance.
    # @return [Redis::Namespace, Redis::Distributed]
    def redis
      Resque.backend.store
    end

    # @return [Redis::Namespace, Redis::Distributed]
    def self.redis
      Resque.backend.store
    end

    # @overload (see Resque::Coder#encode)
    # @param (see Resque::Coder#encode)
    # @return (see Resque::Coder#encode)
    # @raise (see Resque::Coder#encode)
    def encode(object)
      Resque.coder.encode(object)
    end

    # @overload (see Resque::Coder#decode)
    # @param (see Resque::Coder#decode)
    # @return (see Resque::Coder#decode)
    # @raise (see Resque::Coder#decode)
    def decode(object)
      Resque.coder.decode(object)
    end

    # Returns an array of all worker objects.
    # @return [Array<Resque::Worker>]
    def self.all
      redis.smembers(REDIS_WORKERS_KEY).map { |id| find(id) }.compact
    end

    # Returns an array of all worker objects currently processing
    # jobs.
    # @return [Array<Resque::Worker>]
    def self.working
      names = all
      return [] unless names.any?

      names.map! { |name| "#{REDIS_SINGLE_WORKER_KEY}:#{name}" }

      keys_values = if redis.kind_of?(Redis::Distributed)
        Hash[*names.collect do |name|
          [name, redis.get(name)]
        end]
      else
        redis.mapped_mget(*names)
      end

      keys_values.map do |key, value|
        next if value.nil? || value.empty?

        find key.sub("#{REDIS_SINGLE_WORKER_KEY}:", '')
      end.compact
    end

    # Returns a single worker object. Accepts a string id.
    # @param worker_id [String]
    # @return [Resque::Worker]
    def self.find(worker_id)
      if exists?(worker_id)
        worker_id = worker_id.force_encoding('BINARY') # covnert to binary
        worker_id = worker_id.encode('UTF-8', invalid: :replace, undef: :replace) # convert to valid UTF8
        queues = worker_id.split(':')[-1].split(',')
        worker = Worker.new(queues)
        worker.to_s = worker_id
        worker
      else
        nil
      end
    end

    # Alias of `find`
    # @overload (see Resque::WorkerRegistry::find)
    # @param (see Resque::WorkerRegistry::find)
    # @return (see Resque::WorkerRegistry::find)
    def self.attach(worker_id)
      find(worker_id)
    end

    # Given a string worker id, return a boolean indicating whether the
    # worker exists
    # @param worker_id [String]
    # @return [Boolean]
    def self.exists?(worker_id)
      redis.sismember(REDIS_WORKERS_KEY, worker_id)
    end

    # Remove registered worker by it's id
    # @param worker_id [String]
    # @return [void]
    def self.remove(worker_id)
      worker = find(worker_id)
      new(worker).unregister
    end

    # @param worker [Resque::Worker]
    def initialize(worker)
      @worker = worker
    end

    # Markes this as a worker in the underlying backend.
    # @return void
    def register
      redis.pipelined do
        redis.sadd(REDIS_WORKERS_KEY, @worker)
        started!
      end
    end

    # Removes this worker from the backend's list of workers
    # @return [void]
    def done
      redis.del("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}")
    end

    # Returns a symbol representing the current worker state,
    # which can be either :working or :idle
    # @return [:working, :idle]
    def state
      redis.exists("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}") ? :working : :idle
    end

    # What time did this worker start?
    # Returns nil or an rfc2822-parsable String
    # @return [nil, String]
    def started
      redis.get "#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:started"
    end

    # Instruct the worker to shutdown next time it checks.
    # @return [void]
    def remote_shutdown
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:shutdown", true)
    end

    # Check to see if worker has been instructed to shutdown remotely
    # @return [Boolean]
    def remote_shutdown?
      false | redis.get("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:shutdown")
    end

    # Given a job, tells Redis we're working on it. Useful for seeing
    # what workers are doing and when.
    # @param worker [Resque::Worker]
    # @param job [Resque::Job]
    # @return [void]
    def working_on(worker, job)
      job.worker = worker
      data = encode job.to_h
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}", data)
    end

    # Unregisters ourself as a worker. Useful when shutting down.
    # @param exception [Exception] (nil)
    # @return [void]
    def unregister(exception = nil)
      # If we're still processing a job, make sure it gets logged as a
      # failure.
      if (hash = processing) && !hash.empty?
        job = Job.new(hash['queue'], hash['payload'])
        # Ensure the proper worker is attached to this job, even if
        # it's not the precise instance that died.
        job.worker = @worker
        job.fail(exception || DirtyExit.new)
      end

      redis.pipelined do
        redis.srem(REDIS_WORKERS_KEY, @worker)
        redis.del("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}")
        redis.del("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:started")
        redis.del("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:shutdown")

        Stat.clear("processed:#{@worker}")
        Stat.clear("failed:#{@worker}")
      end
    end

    # Returns a hash explaining the Job we're currently processing, if any.
    # @return [Hash<String, Object>]
    def job
      decode(redis.get("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}")) || {}
    end
    alias_method :processing, :job

    private
    # Tell Redis we've started
    # @api private
    def started!
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:started", Time.now.rfc2822)
    end
  end
end
