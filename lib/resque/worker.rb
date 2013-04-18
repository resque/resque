require 'time'
require 'redis/distributed'
require 'resque/logging'
require 'resque/core_ext/hash'
require 'resque/worker_registry'
require 'resque/errors'
require 'resque/backend'

module Resque
  # A Resque Worker processes jobs. On platforms that support fork(2),
  # the worker will fork off a child to process each job. This ensures
  # a clean slate when beginning the next job and cuts down on gradual
  # memory growth as well as low level failures.
  #
  # It also ensures workers are always listening to signals from you,
  # their master, and can react accordingly.
  class Worker
    include Resque::Logging

    # Boolean indicating whether this worker can or can not fork.
    # Automatically set if a fork(2) fails.
    attr_accessor :cant_fork

    # Config options
    attr_accessor :options

    attr_writer :to_s

    attr_reader :client

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
    def initialize(queues = [], options = {})
      @options = {
        # Termination timeout
        :timeout => 5,
        # Worker's poll interval
        :interval => 5,
        # Run as deamon
        :daemon => false,
        # Path to file file where worker's pid will be save
        :pid_file => nil,
        # Use fork(2) on performing jobs
        :fork_per_job => true,
        # When set to true, forked workers will exit with `exit`, calling any `at_exit` code handlers that have been
        # registered in the application. Otherwise, forked workers exit with `exit!`
        :run_at_exit_hooks => false,
      }
      @options.merge!(options.symbolize_keys)

      @queues = (queues.is_a?(Array) ? queues : [queues]).map { |queue| queue.to_s.strip }
      @shutdown = nil
      @paused = nil
      @cant_fork = false

      @client = @options.fetch(:client) { Backend.new(Resque.backend.store, Resque.logger) }

      validate_queues
    end

    def worker_registry
      @worker_registry ||= WorkerRegistry.new(self)
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
    def work(&block)
      interval = Float(options[:interval])
      startup

      loop do
        break if shutdown?

        pause if should_pause?

        if job = reserve(interval)
          process_job(job, &block)
          @child = nil
        else
          break if interval.zero?
          Resque.logger.debug "Timed out after #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@queues.join(',')}"
        end
      end

      worker_registry.unregister
    rescue Exception => exception
      worker_registry.unregister(exception)
    end

    # DEPRECATED. Processes a single job. If none is given, it will
    # try to produce one. Usually run in the child.
    def process(job = nil, &block)
      return unless job ||= reserve

      job.worker = self
      worker_registry.working_on job
      perform(job, &block)
    ensure
      done_working
    end

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues. Low priority queues
    # can be placed after a splat to ensure execution after all other dynamic
    # queues.
    def queues
      @queues.map do |queue|
        if queue == "*"
          (Resque.queues - @queues).sort
        else
          queue
        end
      end.flatten.uniq
    end

    # Schedule this worker for shutdown. Will finish processing the
    # current job.
    #
    # If passed true, mark the shutdown in Redis to signal a remote shutdown
    def shutdown(remote = false)
      Resque.logger.info 'Exiting...'

      @shutdown = true
      worker_registry.remote_shutdown if remote
    end

    # Kill the child and shutdown immediately.
    def shutdown!
      shutdown
      kill_child
    end

    # Should this worker shutdown as soon as current job is finished?
    def shutdown?
      @shutdown || worker_registry.remote_shutdown?
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait 5 seconds, and then a KILL signal if it has not quit
    def kill_child
      return unless @child

      if Process.waitpid(@child, Process::WNOHANG)
        Resque.logger.debug "Child #{@child} already quit."
        return
      end

      signal_child("TERM", @child)

      signal_child("KILL", @child) unless quit_gracefully?(@child)
    rescue SystemCallError
      Resque.logger.debug "Child #{@child} already quit and reaped."
    end

    # send a signal to a child, have it logged.
    def signal_child(signal, child)
      Resque.logger.debug "Sending #{signal} signal to child #{child}"
      Process.kill(signal, child)
    end

    # has our child quit gracefully within the timeout limit?
    def quit_gracefully?(child)
      (options[:timeout].to_f * 10).round.times do |i|
        sleep(0.1)
        return true if Process.waitpid(child, Process::WNOHANG)
      end

      false
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
      all_workers = WorkerRegistry.all
      coordinator = ProcessCoordinator.new
      known_workers = coordinator.worker_pids unless all_workers.empty?
      all_workers.each do |worker|
        host, pid, _ = worker.id.split(':')
        next unless host == hostname
        next if known_workers.include?(pid)
        Resque.logger.debug "Pruning dead worker: #{worker}"
        registry = WorkerRegistry.new(worker)
        registry.unregister
      end
    end

    # How many jobs has this worker processed? Returns an int.
    def processed
      Stat["processed:#{self}"]
    end

    # How many failed jobs has this worker seen? Returns an int.
    def failed
      Stat["failed:#{self}"]
    end

    # Boolean - true if working, false if not
    def working?
      worker_registry.state == :working
    end

    # Boolean - true if idle, false if not
    def idle?
      worker_registry.state == :idle
    end

    def state
      worker_registry.state
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
      @to_s ||= "#{hostname}:#{pid}:#{@queues.join(',')}"
    end
    alias_method :id, :to_s

    # Returns Integer PID of running worker
    def pid
      @pid ||= Process.pid
    end

    # Processes a given job in the child.
    def perform(job)
      procline "Processing #{job.queue} since #{Time.now.to_i} [#{job.payload_class_name}]"
      begin
        run_hook :before_perform, job
        job.perform
        run_hook :after_perform, job
      rescue Object => e
        job.fail(e)
        failed!
      else
        Resque.logger.info "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    def reconnect
      client.reconnect
    end

    protected
    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    def pause_processing
      Resque.logger.info "USR2 received; pausing job processing"
      @paused = true
    end

    def hostname
      Socket.gethostname
    end

    # Not every platform supports fork. Here we do our magic to
    # determine if yours does.
    def fork(job,&block)
      return unless will_fork?

      begin
        # IronRuby doesn't support `Kernel.fork` yet
        if Kernel.respond_to?(:fork)
          # Only run before_fork hooks if we're actually going to fork
          # (after checking @cant_fork)
          if will_fork?
            run_hook :before_fork, job
            Kernel.fork(&block)
          end
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
      procline "Starting"
      daemonize if options[:daemonize]
      write_pid_file(options[:pid_file]) if options[:pid_file]
      enable_gc_optimizations
      register_signal_handlers
      prune_dead_workers
      run_hook :before_first_fork, self
      worker_registry.register

      # Fix buffering so we can `rake resque:work > resque.log` and
      # get output from the child in there.
      $stdout.sync = true
    end

    # Daemonize process (ruby 1.9 only)
    def daemonize
      if Process.respond_to?(:daemon)
        Process.daemon(true)
      else
        Kernel.warn "Running process as daemon requires ruby >= 1.9"
      end
    end

    # Save worker's pid to file
    def write_pid_file(path = nil)
      File.open(path, 'w'){ |f| f << self.pid } if path
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
        # The signal QUIT & USR1 is in use by the JVM and will not work correctly on jRuby
        unless jruby?
          trap('QUIT') { shutdown   }
          trap('USR1') { kill_child }
        end
        trap('USR2') { pause_processing }
        trap('CONT') { unpause_processing }
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

    # Tell Redis we've processed a job.
    def processed!
      Stat << "processed"
      Stat << "processed:#{self}"
    end


    # Tells Redis we've failed a job.
    def failed!
      Stat << "failed"
      Stat << "failed:#{self}"
    end

    def will_fork?
      !@cant_fork && options[:fork_per_job]
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   resque-VERSION: STRING
    def procline(string)
      $0 = "resque-#{Resque::Version}: #{string}"
      Resque.logger.debug $0
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

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    def done_working
      processed!
      worker_registry.done
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

    def wait_for_child
      srand # Reseeding
      procline "Forked #{@child} at #{Time.now.to_i}"
      begin
        Process.waitpid(@child)
      rescue SystemCallError
        nil
      end
    end

    def process_job(job, &block)
      Resque.logger.info "got: #{job.inspect}"
      job.worker = self
      worker_registry.working_on job

      @child = fork(job) do
        reconnect
        run_hook :after_fork, job
        unregister_signal_handlers
        perform(job, &block)
        exit! unless options[:run_at_exit_hooks]
      end

      if @child
        wait_for_child
        job.fail(DirtyExit.new($?.to_s)) if $?.signaled?
      else
        reconnect if will_fork?
        perform(job, &block)
      end
      done_working
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    def reserve(interval = 5)
      multi_queue = MultiQueue.from_queues(queues)

      if interval < 1
        begin
          queue, job = multi_queue.pop(true)
        rescue ThreadError
          queue, job = nil
        end
      else
        queue, job = multi_queue.poll(interval)
      end

      Resque.logger.debug "Found job on #{queue}"
      Job.new(queue.name, job) if (queue && job)
    end
  end
end
