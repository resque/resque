require 'time'
require 'set'
require 'redis/distributed'
require 'resque/logging'
require 'resque/core_ext/hash'
require 'resque/worker_registry'
require 'resque/worker_queue_list'
require 'resque/worker_hooks'
require 'resque/child_process'
require 'resque/errors'
require 'resque/backend'
require 'resque/ioawaiter'

module Resque
  # A Resque Worker processes jobs. On platforms that support fork(2),
  # the worker will fork off a child to process each job. This ensures
  # a clean slate when beginning the next job and cuts down on gradual
  # memory growth as well as low level failures.
  #
  # It also ensures workers are always listening to signals from you,
  # their master, and can react accordingly.
  class Worker
    # Config options
    attr_accessor :options

    attr_writer :to_s

    attr_reader :client

    attr_reader :logger

    attr_reader :worker_queues

    attr_reader :worker_hooks

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
      @options = default_options.merge(options.symbolize_keys)
      @worker_queues = WorkerQueueList.new(queues)
      @shutdown = nil
      @paused = nil
      @logger = @options.delete(:logger)
      @worker_hooks = WorkerHooks.new(logger)

      @client = @options.fetch(:client) { Backend.new(Resque.backend.store, @logger) }

      @awaiter = @options.fetch(:awaiter) { IOAwaiter.new }

      if @worker_queues.empty?
        raise NoQueueError.new("Please give each worker at least one queue.")
      end
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
      startup
      work_loop(&block)
      worker_registry.unregister
    rescue Exception => exception
      worker_registry.unregister(exception)
    end

    # Jobs are pulled from a queue and processed.
    def work_loop(&block)
      interval = Float(options[:interval])
      loop do
        break if shutdown?
        pause if should_pause?

        job = reserve(interval)
        if job
          process_job(job, &block)
        else
          break if interval.zero?
          logger.debug "Timed out after #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@worker_queues}"
        end
      end

    end

    # DEPRECATED. Processes a single job. If none is given, it will
    # try to produce one. Usually run in the child.
    def process(job = nil, &block)
      return unless job ||= reserve

      worker_registry.working_on self, job
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
      @worker_queues.search_order
    end

    # Schedule this worker for shutdown. Will finish processing the
    # current job.
    #
    # If passed true, mark the shutdown in Redis to signal a remote shutdown
    def shutdown(remote = false)
      logger.info 'Exiting...'

      @shutdown = true
      worker_registry.remote_shutdown if remote
    end

    # Kill the child and shutdown immediately.
    def shutdown!
      shutdown
      @child.kill
    end

    # Should this worker shutdown as soon as current job is finished?
    def shutdown?
      @shutdown || worker_registry.remote_shutdown?
    end

    # are we paused?
    def should_pause?
      @paused
    end
    alias :paused? :should_pause?

    def pause
      worker_hooks.run_hook :before_pause, self
      @awaiter.await
      @paused = false
      worker_hooks.run_hook :after_pause, self
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
        host, pid, workers_queues_raw = worker.id.split(':')
        workers_queues = workers_queues_raw.split(",")
        unless worker_queues.all_queues? || (workers_queues.to_set == worker_queues.to_set)
          # If the worker we are trying to prune does not belong to the queues
          # we are listening to, we should not touch it. 
          # Attempt to prune a worker from different queues may easily result in
          # an unknown class exception, since that worker could easily be even 
          # written in different language.
          next
        end        
        next unless host == hostname
        next if known_workers.include?(pid)
        logger.debug "Pruning dead worker: #{worker}"
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
      @to_s ||= "#{hostname}:#{pid}:#{@worker_queues}"
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
        worker_hooks.run_hook :before_perform, job
        job.perform
        worker_hooks.run_hook :after_perform, job
      rescue Object => e
        job.fail(e)
        failed!
      else
        logger.info "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    def will_fork?
      options[:fork_per_job]
    end

    protected
    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    def pause_processing
      logger.info "USR2 received; pausing job processing"
      @paused = true
    end

    def hostname
      Socket.gethostname
    end

    # Runs all the methods needed when a worker begins its lifecycle.
    def startup
      procline "Starting"
      daemonize if options[:daemonize]
      write_pid_file(options[:pid_file]) if options[:pid_file]
      enable_gc_optimizations
      register_signal_handlers
      prune_dead_workers
      worker_hooks.run_hook :before_first_fork, self
      worker_registry.register

      # Fix buffering so we can `rake resque:work > resque.log` and
      # get output from the child in there.
      $stdout.sync = true
    end

    # Daemonize process (ruby 1.9 only)
    def daemonize
      if Process.respond_to?(:daemon)
        Process.daemon(true, true)
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
          trap('USR1') { @child.kill }
        end
        trap('USR2') { pause_processing }
        trap('CONT') { unpause_processing }
      rescue ArgumentError
        warn "Signals QUIT, USR1, USR2, and/or CONT not supported."
      end

      logger.debug "Registered signals"
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


    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   resque-VERSION: STRING
    def procline(string)
      $0 = "resque-#{Resque::Version}: #{string}"
      logger.debug $0
    end

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    def done_working
      processed!
      worker_registry.done
    end

    def process_job(job, &block)
      logger.info "got: #{job.inspect}"

      worker_registry.working_on self, job

      fork_for_child(job, &block)

    ensure
      done_working
    end

    def fork_for_child(job, &block)
      @child = ChildProcess.new(self)
      @child.fork_and_perform(job, &block)
    ensure
      @child = nil
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    def reserve(interval = 5)
      multi_queue = MultiQueue.from_queues(@worker_queues.search_order)

      if interval < 1
        begin
          queue, job = multi_queue.pop(true)
        rescue ThreadError
          queue, job = nil
        end
      else
        queue, job = multi_queue.poll(interval)
      end

      logger.debug "Found job on #{queue}"
      Job.new(queue.name, job) if (queue && job)
    end

  private
    def default_options
      {
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
        # the logger we're going to use.
        :logger => Resque.logger,
      }
    end

  end

end
