# This class handles registering/unregistering/updating worker status in Redis
module Resque
  class WorkerRegistry
    REDIS_WORKERS_KEY = :workers
    REDIS_SINGLE_WORKER_KEY = :worker

    # Direct access to the Redis instance.
    def redis
      Resque.backend.store
    end

    def self.redis
      Resque.backend.store
    end

    def encode(object)
      Resque.coder.encode(object)
    end

    def decode(object)
      Resque.coder.decode(object)
    end

    # Returns an array of all worker objects.
    def self.all
      redis.smembers(REDIS_WORKERS_KEY).map { |id| find(id) }.compact
    end

    # Returns an array of all worker objects currently processing
    # jobs.
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
    def self.find(worker_id)
      if exists?(worker_id)
        queues = worker_id.split(':')[-1].split(',')
        worker = Worker.new(queues)
        worker.to_s = worker_id
        worker
      else
        nil
      end
    end

    # Alias of `find`
    def self.attach(worker_id)
      find(worker_id)
    end

    # Given a string worker id, return a boolean indicating whether the
    # worker exists
    def self.exists?(worker_id)
      redis.sismember(REDIS_WORKERS_KEY, worker_id)
    end

    # Remove registered worker by it's id
    def self.remove(worker_id)
      worker = find(worker_id)
      new(worker).unregister
    end

    def initialize(worker)
      @worker = worker
    end

    def register
      redis.pipelined do
        redis.sadd(REDIS_WORKERS_KEY, @worker)
        started!
      end
    end

    def done
      redis.del("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}")
    end

    # Returns a symbol representing the current worker state,
    # which can be either :working or :idle
    def state
      redis.exists("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}") ? :working : :idle
    end

    # What time did this worker start? Returns an instance of `Time`
    def started
      redis.get "#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:started"
    end

    def remote_shutdown
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:shutdown", true)
    end

    def remote_shutdown?
      redis.get("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:shutdown")
    end

    # Given a job, tells Redis we're working on it. Useful for seeing
    # what workers are doing and when.
    def working_on(job)
      data = encode job.to_h
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}", data)
    end

    # Unregisters ourself as a worker. Useful when shutting down.
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
    def job
      decode(redis.get("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}")) || {}
    end
    alias_method :processing, :job

    private
    # Tell Redis we've started
    def started!
      redis.set("#{REDIS_SINGLE_WORKER_KEY}:#{@worker}:started", Time.now.rfc2822)
    end
  end
end
