module Resque
  class Worker
    attr_accessor :logger
    attr_writer   :to_s


    #
    # worker class methods
    #

    def self.all
      redis.smembers(:workers).map { |id| find(id) }
    end

    def self.working
      names = all
      return [] unless names.any?
      names.map! { |name| "worker:#{name}" }
      redis.mapped_mget(*names).keys.map do |key|
        find key.sub("worker:", '')
      end
    end

    def self.find(worker_id)
      if exists? worker_id
        queues = worker_id.split(':')[-1].split(',')
        worker = new(*queues)
        worker.to_s = worker_id
        worker
      else
        nil
      end
    end

    def self.attach(worker_id)
      find(worker_id)
    end

    def self.exists?(worker_id)
      redis.sismember(:workers, worker_id)
    end


    #
    # setup
    #

    def initialize(*queues)
      @queues = queues
      validate_queues
    end

    class NoQueueError < RuntimeError; end

    def validate_queues
      if @queues.nil? || @queues.empty?
        raise NoQueueError.new("Please give each worker at least one queue.")
      end
    end


    #
    # main loop / processing
    #

    def work(interval = 5, &block)
      $0 = "resque: Starting"
      startup

      loop do
        break if @shutdown

        if job = reserve
          log "Got #{job.inspect}"

          if @child = fork
            $0 = "resque: Forked #{@child} at #{Time.now.to_i}"
            Process.wait
          else
            $0 = "resque: Processing #{job.queue} since #{Time.now.to_i}"
            process(job, &block)
            exit!
          end

          @child = nil
        else
          break if interval.to_i == 0
          log "Sleeping"
          $0 = "resque: Waiting for #{@queues.join(',')}"
          sleep interval.to_i
        end
      end

    ensure
      unregister_worker
    end

    def process(job = nil)
      return unless job ||= reserve

      begin
        working_on job
        job.perform
      rescue Object => e
        log "#{job.inspect} failed: #{e.inspect}"
        job.fail(e)
        failed!
      else
        log "#{job.inspect} done processing"
      ensure
        yield job if block_given?
        done_working
      end
    end

    def reserve
      queues.each do |queue|
        if job = Resque::Job.reserve(queue)
          return job
        end
      end

      nil
    end

    # Passing a splat means you want every queue.
    def queues
      @queues[0] == "*" ? Resque.queues : @queues
    end


    #
    # startup / teardown
    #

    def startup
      register_signal_handlers
      prune_dead_workers
      register_worker
    end

    def register_signal_handlers
      trap('TERM') { shutdown  }
      trap('INT')  { shutdown  }
      trap('HUP')  { shutdown! }
    end

    def shutdown
      log 'Exiting...'
      @shutdown = true
    end

    def shutdown!
      shutdown
      Process.kill("KILL", @child) if @child
    end

    def prune_dead_workers
      Worker.all.each do |worker|
        host, pid, queues = worker.id.split(':')
        next unless host == hostname
        next if worker_pids.include?(pid)
        worker.unregister_worker
      end
    end

    def register_worker
      redis.sadd(:workers, self)
      started!
    end

    def unregister_worker
      done_working

      redis.srem(:workers, self)
      redis.del("worker:#{self}:started")

      Stat.clear("processed:#{self}")
      Stat.clear("failed:#{self}")
    end

    def working_on(job)
      job.worker = self
      data = encode \
        :queue   => job.queue,
        :run_at  => Time.now.to_s,
        :payload => job.payload
      redis.set("worker:#{self}", data)
    end

    def done_working
      processed!
      redis.del("worker:#{self}")
    end


    #
    # query the worker
    #

    def processed
      Stat["processed:#{self}"]
    end

    def processed!
      Stat.incr("processed")
      Stat.incr("processed:#{self}")
    end

    def failed
      Stat["failed:#{self}"]
    end

    def failed!
      Stat.incr("failed")
      Stat.incr("failed:#{self}")
    end

    def started
      redis.get "worker:#{self}:started"
    end

    def started!
      redis.set("worker:#{self}:started", Time.now.to_s)
    end

    def job
      decode(redis.get("worker:#{self}")) || {}
    end
    alias_method :processing, :job

    def working?
      state == :working
    end

    def idle?
      state == :idle
    end

    def state
      redis.exists("worker:#{self}") ? :working : :idle
    end

    def ==(other)
      to_s == other.to_s
    end

    def inspect
      "#<Worker #{to_s}>"
    end

    def to_s
      @to_s ||= "#{hostname}:#{Process.pid}:#{@queues.join(',')}"
    end
    alias_method :id, :to_s

    def hostname
      @hostname ||= `hostname`.chomp
    end

    # Finds pids of all the other workers.
    # Used when pruning dead workers on startup.
    def worker_pids
      `ps -e -o pid,command | grep [r]esque`.split("\n").map do |line|
        line.split(' ')[0]
      end
    end


    #
    # randomness
    #

    def log(message)
      puts "*** #{message}" if logger
    end

    def redis
      Resque.redis
    end

    def self.redis
      Resque.redis
    end

    def encode(*args)
      Resque.encode(*args)
    end

    def decode(*args)
      Resque.decode(*args)
    end
  end
end
