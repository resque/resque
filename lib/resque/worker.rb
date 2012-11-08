require 'time'

module Resque
  # A Resque Worker processes jobs. On platforms that support fork(2),
  # the worker will fork off a child to process each job. This ensures
  # a clean slate when beginning the next job and cuts down on gradual
  # memory growth as well as low level failures.
  #
  # It also ensures workers are always listening to signals from you,
  # their master, and can react accordingly.
  class Worker
    extend  Resque::Helpers
    include Resque::Helpers
    include Resque::Logging

    # Boolean indicating whether this worker can or can not fork.
    # Automatically set if a fork(2) fails.
    attr_accessor :cant_fork

    attr_accessor :term_timeout

    attr_writer :to_s

    # Returns an array of all worker objects.
    def self.all
      Array(redis.smembers(:workers)).map { |id| find(id) }.compact
    end

    # Returns an array of all worker objects currently processing
    # jobs.
    def self.working
      names = all
      return [] unless names.any?

      names.map! { |name| "worker:#{name}" }

      reportedly_working = {}

      begin
        reportedly_working = redis.mapped_mget(*names).reject do |key, value|
          value.nil? || value.empty?
        end
      rescue Redis::Distributed::CannotDistribute
        names.each do |name|
          value = redis.get name
          reportedly_working[name] = value unless value.nil? || value.empty?
        end
      end

      reportedly_working.keys.map do |key|
        find key.sub("worker:", '')
      end.compact
    end

    # Returns a single worker object. Accepts a string id.
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

    # Alias of `find`
    def self.attach(worker_id)
      find(worker_id)
    end

    # Given a string worker id, return a boolean indicating whether the
    # worker exists
    def self.exists?(worker_id)
      redis.sismember(:workers, worker_id)
    end

    # Workers should be initialized with an array of string queue
    # names. The order is important: a Worker will check the first
    # queue given for a job. If none is found, it will check the
    # second queue name given. If a job is found, it will be
    # processed. Upon completion, the Worker will again check the
    # first queue given, and so forth. In this way the queue list
    # passed to a Worker on startup defines the priorities of queues.
    #
    # If passed a single "*", this Worker will operate on all queues
    # in alphabetical order. Queues can be dynamically added or
    # removed without needing to restart workers using this method.
    def initialize(*queues)
      @queues = queues.map { |queue| queue.to_s.strip }
      @shutdown = nil
      @paused = nil
      validate_queues
    end

    # A worker must be given a queue, otherwise it won't know what to
    # do with itself.
    #
    # You probably never need to call this.
    def validate_queues
      if @queues.nil? || @queues.empty?
        raise NoQueueError.new("Please give each worker at least one queue.")
      end
    end

    # This is the main workhorse method. Called on a Worker instance,
    # it begins the worker life cycle.
    #
    # The following events occur during a worker's life cycle:
    #
    # 1. Startup:   Signals are registered, dead workers are pruned,
    #               and this worker is registered.
    # 2. Work loop: Jobs are pulled from a queue and processed.
    # 3. Teardown:  This worker is unregistered.
    #
    # Can be passed a float representing the polling frequency.
    # The default is 5 seconds, but for a semi-active site you may
    # want to use a smaller value.
    #
    # Also accepts a block which will be passed the job as soon as it
    # has completed processing. Useful for testing.
    def work(interval = 5.0, &block)
      interval = Float(interval)
      $0 = "resque: Starting"
      startup

      loop do
        break if shutdown?

        pause if should_pause?

        if job = reserve(interval)
          Resque.logger.info "got: #{job.inspect}"
          job.worker = self
          working_on job

          if @child = fork(job)
            srand # Reseeding
            procline "Forked #{@child} at #{Time.now.to_i}"
            begin
              Process.waitpid(@child)
            rescue SystemCallError
              nil
            end
            job.fail(DirtyExit.new($?.to_s)) if $?.signaled?
          else
            unregister_signal_handlers if will_fork?
            procline "Processing #{job.queue} since #{Time.now.to_i}"
            reconnect
            perform(job, &block)
            exit!(true) if will_fork?
          end

          done_working
          @child = nil
        else
          break if interval.zero?
          Resque.logger.debug "Timed out after #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@queues.join(',')}"
        end
      end

      unregister_worker
    rescue Exception => exception
      unregister_worker(exception)
    end

    # DEPRECATED. Processes a single job. If none is given, it will
    # try to produce one. Usually run in the child.
    def process(job = nil, &block)
      return unless job ||= reserve

      job.worker = self
      working_on job
      perform(job, &block)
    ensure
      done_working
    end

    # Processes a given job in the child.
    def perform(job)
      begin
        run_hook :after_fork, job if will_fork?
        run_hook :before_perform, job
        job.perform
        run_hook :after_perform, job
      rescue Object => e
        Resque.logger.info "#{job.inspect} failed: #{e.inspect}"
        begin
          job.fail(e)
        rescue Object => e
          Resque.logger.info "Received exception when reporting failure: #{e.inspect}"
        end
        failed!
      else
        Resque.logger.info "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    def reserve(interval = 5.0)
      interval = interval.to_i
      multi_queue = MultiQueue.new(
        queues.map {|queue| Queue.new(queue, Resque.redis, Resque.coder) },
        Resque.redis)

      if interval < 1
        begin
          queue, job = multi_queue.pop(true)
        rescue ThreadError
          queue, job = nil
        end
      else
        queue, job = multi_queue.poll(interval.to_i)
      end

      Resque.logger.debug "Found job on #{queue}"
      Job.new(queue.name, job) if queue && job
    end

    # Reconnect to Redis to avoid sharing a connection with the parent,
    # retry up to 3 times with increasing delay before giving up.
    def reconnect
      tries = 0
      begin
        redis.client.reconnect
      rescue Redis::BaseConnectionError
        if (tries += 1) <= 3
          Resque.logger.info "Error reconnecting to Redis; retrying"
          sleep(tries)
          retry
        else
          Resque.logger.info "Error reconnecting to Redis; quitting"
          raise
        end
      end
    end

    # Reconnect to Redis to avoid sharing a connection with the parent,
    # retry up to 3 times with increasing delay before giving up.
    def reconnect
      tries = 0
      begin
        redis.client.reconnect
      rescue Redis::BaseConnectionError
        if (tries += 1) <= 3
          Resque.logger.info "Error reconnecting to Redis; retrying"
          sleep(tries)
          retry
        else
          Resque.logger.info "Error reconnecting to Redis; quitting"
          raise
        end
      end
    end

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues. Low priority queues
    # can be placed after a splat to ensure execution after all other dynamic
    # queues.
    def queues
      @queues.map {|queue| queue == "*" ? (Resque.queues - @queues).sort : queue }.flatten.uniq
    end

    # Not every platform supports fork. Here we do our magic to
    # determine if yours does.
    def fork(job)
      return if @cant_fork
      
      # Only run before_fork hooks if we're actually going to fork
      # (after checking @cant_fork)
      run_hook :before_fork, job if will_fork?

      begin
        # IronRuby doesn't support `Kernel.fork` yet
        if Kernel.respond_to?(:fork)
          Kernel.fork if will_fork?
        else
          raise NotImplementedError
        end
      rescue NotImplementedError
        @cant_fork = true
        nil
      end
    end

    # Runs all the methods needed when a worker begins its lifecycle.
    def startup
      enable_gc_optimizations
      register_signal_handlers
      prune_dead_workers
      run_hook :before_first_fork, self
      register_worker

      # Fix buffering so we can `rake resque:work > resque.log` and
      # get output from the child in there.
      $stdout.sync = true
    end

    # Enables GC Optimizations if you're running REE.
    # http://www.rubyenterpriseedition.com/faq.html#adapt_apps_for_cow
    def enable_gc_optimizations
      if GC.respond_to?(:copy_on_write_friendly=)
        GC.copy_on_write_friendly = true
      end
    end

    # Registers the various signal handlers a worker responds to.
    #
    # TERM: Shutdown immediately, stop processing jobs.
    #  INT: Shutdown immediately, stop processing jobs.
    # QUIT: Shutdown after the current job has finished processing.
    # USR1: Kill the forked child immediately, continue processing jobs.
    # USR2: Don't process any new jobs
    # CONT: Start processing jobs again after a USR2
    def register_signal_handlers
      trap('TERM') { shutdown!  }
      trap('INT')  { shutdown!  }

      begin
        trap('QUIT') { shutdown   }
        trap('USR1') { kill_child }
        trap('USR2') { pause_processing }
      rescue ArgumentError
        warn "Signals QUIT, USR1, USR2, and/or CONT not supported."
      end

      Resque.logger.debug "Registered signals"
    end

    def unregister_signal_handlers
      trap('TERM') { raise TermException.new("SIGTERM") }
      trap('INT', 'DEFAULT')

      begin
        trap('QUIT', 'DEFAULT')
        trap('USR1', 'DEFAULT')
        trap('USR2', 'DEFAULT')
      rescue ArgumentError
      end
    end

    # Schedule this worker for shutdown. Will finish processing the
    # current job.
    def shutdown
      Resque.logger.info 'Exiting...'
      @shutdown = true
    end

    # Kill the child and shutdown immediately.
    def shutdown!
      shutdown
      kill_child
    end

    # Should this worker shutdown as soon as current job is finished?
    def shutdown?
      @shutdown
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait 5 seconds, and then a KILL signal if it has not quit
    def kill_child
      if @child
        unless Process.waitpid(@child, Process::WNOHANG)
          Resque.logger.debug "Sending TERM signal to child #{@child}"
          Process.kill("TERM", @child)
          (term_timeout.to_f * 10).round.times do |i|
            sleep(0.1)
            return if Process.waitpid(@child, Process::WNOHANG)
          end
          Resque.logger.debug "Sending KILL signal to child #{@child}"
          Process.kill("KILL", @child)
        else
          Resque.logger.debug "Child #{@child} already quit."
        end
      end
    rescue SystemCallError
      Resque.logger.debug "Child #{@child} already quit and reaped."
    end

    # are we paused?
    def should_pause?
      @paused
    end
    alias :paused? :should_pause?

    def pause
      rd, wr = IO.pipe
      trap('CONT') {
        Resque.logger.info "CONT received; resuming job processing"
        @paused = false
        wr.write 'x'
        wr.close
      }
      run_hook :before_pause, self
      rd.read 1
      rd.close
      run_hook :after_pause, self
    end

    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    def pause_processing
      Resque.logger.info "USR2 received; pausing job processing"
      @paused = true
    end

    # Looks for any workers which should be running on this server
    # and, if they're not, removes them from Redis.
    #
    # This is a form of garbage collection. If a server is killed by a
    # hard shutdown, power failure, or something else beyond our
    # control, the Resque workers will not die gracefully and therefore
    # will leave stale state information in Redis.
    #
    # By checking the current Redis state against the actual
    # environment, we can determine if Redis is old and clean it up a bit.
    def prune_dead_workers
      all_workers = Worker.all
      known_workers = worker_pids unless all_workers.empty?
      all_workers.each do |worker|
        host, pid, queues = worker.id.split(':')
        next unless host == hostname
        next if known_workers.include?(pid)
        Resque.logger.debug "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    # Registers ourself as a worker. Useful when entering the worker
    # lifecycle on startup.
    def register_worker
      redis.sadd(:workers, self)
      started!
    end

    # Runs a named hook, passing along any arguments.
    def run_hook(name, *args)
      return unless hooks = Resque.send(name)
      msg = "Running #{name} hooks"
      msg << " with #{args.inspect}" if args.any?
      Resque.logger.info msg

      hooks.each do |hook|
        args.any? ? hook.call(*args) : hook.call
      end
    end

    # Unregisters ourself as a worker. Useful when shutting down.
    def unregister_worker(exception = nil)
      # If we're still processing a job, make sure it gets logged as a
      # failure.
      if (hash = processing) && !hash.empty?
        job = Job.new(hash['queue'], hash['payload'])
        # Ensure the proper worker is attached to this job, even if
        # it's not the precise instance that died.
        job.worker = self
        job.fail(exception || DirtyExit.new)
      end

      redis.srem(:workers, self)
      redis.del("worker:#{self}")
      redis.del("worker:#{self}:started")

      Stat.clear("processed:#{self}")
      Stat.clear("failed:#{self}")
    end

    # Given a job, tells Redis we're working on it. Useful for seeing
    # what workers are doing and when.
    def working_on(job)
      data = encode \
        :queue   => job.queue,
        :run_at  => Time.now.rfc2822,
        :payload => job.payload
      redis.set("worker:#{self}", data)
    end

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    def done_working
      processed!
      redis.del("worker:#{self}")
    end

    # How many jobs has this worker processed? Returns an int.
    def processed
      Stat["processed:#{self}"]
    end

    # Tell Redis we've processed a job.
    def processed!
      Stat << "processed"
      Stat << "processed:#{self}"
    end

    # How many failed jobs has this worker seen? Returns an int.
    def failed
      Stat["failed:#{self}"]
    end

    # Tells Redis we've failed a job.
    def failed!
      Stat << "failed"
      Stat << "failed:#{self}"
    end

    # What time did this worker start? Returns an instance of `Time`
    def started
      redis.get "worker:#{self}:started"
    end

    # Tell Redis we've started
    def started!
      redis.set("worker:#{self}:started", Time.now.rfc2822)
    end

    # Returns a hash explaining the Job we're currently processing, if any.
    def job
      decode(redis.get("worker:#{self}")) || {}
    end
    alias_method :processing, :job

    # Boolean - true if working, false if not
    def working?
      state == :working
    end

    # Boolean - true if idle, false if not
    def idle?
      state == :idle
    end
    
    def will_fork?
      !(@cant_fork || $TESTING)
    end

    # Returns a symbol representing the current worker state,
    # which can be either :working or :idle
    def state
      redis.exists("worker:#{self}") ? :working : :idle
    end

    # Is this worker the same as another worker?
    def ==(other)
      to_s == other.to_s
    end

    def inspect
      "#<Worker #{to_s}>"
    end

    # The string representation is the same as the id for this worker
    # instance. Can be used with `Worker.find`.
    def to_s
      @to_s ||= "#{hostname}:#{Process.pid}:#{@queues.join(',')}"
    end
    alias_method :id, :to_s

    def hostname
      Socket.gethostname
    end

    # Returns Integer PID of running worker
    def pid
      Process.pid
    end

    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    def worker_pids
      if RUBY_PLATFORM =~ /solaris/
        solaris_worker_pids
      elsif RUBY_PLATFORM =~ /mingw32/
        windows_worker_pids
      else
        linux_worker_pids
      end
    end

    # Find Resque worker pids on Windows.
    #
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    def windows_worker_pids
      `tasklist  /FI "IMAGENAME eq ruby.exe" /FO list`.split($/).select { |line| line =~ /^PID:/}.collect{ |line| line.gsub /PID:\s+/, '' }
    end

    # Find Resque worker pids on Linux and OS X.
    #
    def linux_worker_pids
      get_worker_pids('ps -A -o pid,command')
    end

    # Find Resque worker pids on Solaris.
    #
    def solaris_worker_pids
      get_worker_pids('ps -A -o pid,args')
    end

    # Find worker pids - platform independent
    #
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    def get_worker_pids(command)
       active_worker_pids = []
       output = %x[#{command}]  # output format of ps must be ^<PID> <COMMAND WITH ARGS>
       raise 'System call for ps command failed. Please make sure that you have a compatible ps command in the path!' unless $?.success?
       output.split($/).each{|line|
        next unless line =~ /resque/i
        next if line =~ /resque-web/
        active_worker_pids.push line.split(' ')[0]
       }
       active_worker_pids
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   resque-VERSION: STRING
    def procline(string)
      $0 = "resque-#{Resque::Version}: #{string}"
      Resque.logger.debug $0
    end
  end
end
