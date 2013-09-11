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
require 'resque/options'
require 'resque/signal_trapper'

module Resque
  # A Resque Worker processes jobs. On platforms that support fork(2),
  # the worker will fork off a child to process each job. This ensures
  # a clean state when beginning the next job and cuts down on gradual
  # memory growth as well as low level failures.
  #
  # It also ensures workers are always listening to signals from you,
  # their master, and can react accordingly.
  class Worker
    # Config options
    # @return [Hash<Symbol,Object>] (see #initialize)
    attr_accessor :options

    attr_writer :to_s

    # @return [Resque::Backend]
    attr_reader :client

    # @return [#warn,#unknown,#error,#info,#debug] duck-typed ::Logger
    attr_reader :logger

    # @return [WorkerQueueList]
    attr_reader :worker_queues

    # @return [WorkerHooks]
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
    #
    # @param queues (see WorkerQueueList#initialize)
    # @param options [Hash<Symbol,Object>]
    # @option options [Boolean] :graceful_term
    # @option options [#warn,#unknown,#error,#info,#debug] :logger duck-typed ::Logger
    # @option options [#await] :awaiter (IOAwaiter.new)
    # @option options [Resque::Backend] :client
    def initialize(queues = [], options = {})
      @options = Options.new(options)
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

    # @return [Resque::WorkerRegistry]
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
    # @yieldparam (see #work_loop)
    # @yieldreturn (see #work_loop)
    # @return [void]
    def work(&block)
      startup
      work_loop(&block)
      worker_registry.unregister
    rescue Exception => exception
      worker_registry.unregister(exception)
      raise exception
    end

    # Jobs are pulled from a queue and processed.
    # @yieldparam (see #process_job)
    # @yieldreturn (see #process_job)
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
    # @param job [Resque::Job] (#reserve)
    # @yieldparam (see #perform)
    # @yieldreturn (see #perform)
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
    # @return (see WorkerQueueList#search_order)
    def queues
      @worker_queues.search_order
    end

    # Schedule this worker for shutdown. Will finish processing the
    # current job.
    #
    # If passed true, mark the shutdown in Redis to signal a remote shutdown
    # @param remote [Boolean] (false)
    # @return [void]
    def shutdown(remote = false)
      logger.info 'Exiting...'

      @shutdown = true
      worker_registry.remote_shutdown if remote
    end

    # Kill the child and shutdown immediately.
    # @return (see Resque::ChildProcess#kill)
    def shutdown!
      shutdown
      @child.kill if @child
    end

    # Should this worker shutdown as soon as current job is finished?
    # @return [Boolean]
    def shutdown?
      @shutdown || worker_registry.remote_shutdown?
    end

    # are we paused?
    # @return [Boolean]
    def should_pause?
      @paused
    end
    alias :paused? :should_pause?

    # Uses the @awaiter to pause execution.
    # Runs :before_pause and after_pause hooks with self as its argument
    # @return [void]
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
    # @return [void]
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
    # @return [Integer]
    def processed
      Stat["processed:#{self}"]
    end

    # How many failed jobs has this worker seen? Returns an int.
    # @return [Integer]
    def failed
      Stat["failed:#{self}"]
    end

    # Boolean - true if working, false if not
    # @return [Boolean]
    def working?
      worker_registry.state == :working
    end

    # true if idle, false if not
    # @return [Boolean]
    def idle?
      worker_registry.state == :idle
    end

    # @return (see Resque::WorkerRegistry#state)
    def state
      worker_registry.state
    end

    # Is this worker the same as another worker?
    # @return [Boolean]
    def ==(other)
      to_s == other.to_s
    end

    # @return [String]
    def inspect
      "#<Worker #{to_s}>"
    end

    # The string representation is the same as the id for this worker
    # instance. Can be used with `Worker.find`.
    # @return [String]
    def to_s
      @to_s ||= "#{hostname}:#{pid}:#{@worker_queues}"
    end
    alias_method :id, :to_s

    # Returns Integer PID of running worker
    # @return [Integer]
    def pid
      @pid ||= Process.pid
    end

    # Processes a given job in the child.
    # @param job [Resque::Job]
    # @yieldparam [Resque::Job] if block was given, yields the job after
    #                           execution is complete regardless of outcome
    # @yieldreturn [void]
    # @return [void]
    def perform(job)
      procline "Processing #{job.queue} since #{Time.now.iso8601} [#{job.payload_class_name}]"
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

    protected
    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    # @return [void]
    def pause_processing
      logger.info "USR2 received; pausing job processing"
      @paused = true
    end

    # @return [String]
    def hostname
      Socket.gethostname
    end

    # Runs all the methods needed when a worker begins its lifecycle.
    # @return [void]
    def startup
      procline "Starting"
      daemonize if options[:daemon]
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

    # Daemonize process (ruby >= 1.9 only)
    # @return [void] Ruby ~>1.8
    # @return [0] Ruby 1.9+ (see Process::daemon)
    # @raise [Errno] on failure
    def daemonize
      if Process.respond_to?(:daemon)
        Process.daemon(true, true)
      else
        Kernel.warn "Running process as daemon requires ruby >= 1.9"
      end
    end

    # Save worker's pid to file
    # @return [void]
    def write_pid_file(path = nil)
      File.open(path, 'w'){ |f| f << self.pid } if path
    end

    # Enables GC Optimizations if you're running REE.
    # http://www.rubyenterpriseedition.com/faq.html#adapt_apps_for_cow
    # @return [void]
    def enable_gc_optimizations
      if GC.respond_to?(:copy_on_write_friendly=)
        GC.copy_on_write_friendly = true
      end
    end

    # Registers the various signal handlers a worker responds to.
    #
    # TERM/INT: Shutdown immediately, stop processing jobs.
    # QUIT: Shutdown after the current job has finished processing.
    # USR1: Kill the forked child immediately, continue processing jobs.
    # USR2: Don't process any new jobs
    # @return [void]
    def register_signal_handlers
      SignalTrapper.trap('TERM') { graceful_term? ? shutdown : shutdown! }
      SignalTrapper.trap('INT')  { shutdown! }

      # these signals are in use by the JVM and will not work correctly on jRuby
      unless jruby?
        SignalTrapper.trap_or_warn('QUIT') { shutdown }
        SignalTrapper.trap_or_warn('USR1') { @child.kill }
      end
      SignalTrapper.trap_or_warn('USR2') { pause_processing }

      logger.debug "Registered signals"
    end

    # @return [Boolean]
    def jruby?
      defined?(JRUBY_VERSION)
    end

    # Tell Redis we've processed a job.
    # @return [void]
    def processed!
      Stat << "processed"
      Stat << "processed:#{self}"
    end

    # Tells Redis we've failed a job.
    # @return [void]
    def failed!
      Stat << "failed"
      Stat << "failed:#{self}"
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   RESQUE_PROCLINE_PREFIXresque-VERSION: STRING
    # @param string [String]
    # @return [void]
    def procline(string)
      $0 = "#{ENV['RESQUE_PROCLINE_PREFIX']}resque-#{Resque::Version}: #{string}"
      logger.debug $0
    end

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    # @return [void]
    def done_working
      processed!
      worker_registry.done
    end

    # @param job [Resque::Job]
    # @yieldparam (see #fork_for_child)
    # @yieldreturn (see #fork_for_child)
    # @return [void]
    def process_job(job, &block)
      logger.info "got: #{job.inspect}"

      worker_registry.working_on self, job

      fork_for_child(job, &block)

    ensure
      done_working
    end

    # @param job [Resque::Job]
    # @yieldparam (see ChildProcess#fork_and_perform)
    # @yieldreturn (see ChildProcess#fork_and_perform)
    # @return [void]
    def fork_for_child(job, &block)
      @child = ChildProcess.new(self)
      @child.fork_and_perform(job, &block)
    ensure
      @child = nil
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    # @param interval [Numeric] (5) positive number (0...Float::INFINITY)
    #                           that is used to determine the popping mechanism
    # @return [Resque::Job] if job was found
    # @return [nil] if no job found
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

      if queue && job
        logger.debug "Found job on #{queue}"
        Job.new(queue.name, job)
      end
    end

    # @return [Boolean]
    def graceful_term?
      options[:graceful_term]
    end
  end
end
