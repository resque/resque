require 'time'
require 'set'
require 'redis/distributed'

module Resque
  # A Resque Worker processes jobs. On platforms that support fork(2),
  # the worker will fork off a child to process each job. This ensures
  # a clean slate when beginning the next job and cuts down on gradual
  # memory growth as well as low level failures.
  #
  # It also ensures workers are always listening to signals from you,
  # their master, and can react accordingly.
  class Worker
    include Resque::Helpers
    extend Resque::Helpers
    include Resque::Logging

    @@all_heartbeat_threads = []
    def self.kill_all_heartbeat_threads
      @@all_heartbeat_threads.each(&:kill).each(&:join)
      @@all_heartbeat_threads = []
    end

    def redis
      Resque.redis
    end
    alias :data_store :redis

    def self.redis
      Resque.redis
    end

    def self.data_store
      self.redis
    end

    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    def encode(object)
      Resque.encode(object)
    end

    # Given a string, returns a Ruby object.
    def decode(object)
      Resque.decode(object)
    end

    attr_accessor :term_timeout

    attr_accessor :pre_shutdown_timeout

    attr_accessor :term_child_signal

    # decide whether to use new_kill_child logic
    attr_accessor :term_child

    # should term kill workers gracefully (vs. immediately)
    # Makes SIGTERM work like SIGQUIT
    attr_accessor :graceful_term

    # When set to true, forked workers will exit with `exit`, calling any `at_exit` code handlers that have been
    # registered in the application. Otherwise, forked workers exit with `exit!`
    attr_accessor :run_at_exit_hooks

    attr_writer :fork_per_job
    attr_writer :hostname
    attr_writer :to_s
    attr_writer :pid

    # Returns an array of all worker objects.
    def self.all
      data_store.worker_ids.map { |id| find(id, :skip_exists => true) }.compact
    end

    # Returns an array of all worker objects currently processing
    # jobs.
    def self.working
      names = all
      return [] unless names.any?

      reportedly_working = {}

      begin
        reportedly_working = data_store.workers_map(names).reject do |key, value|
          value.nil? || value.empty?
        end
      rescue Redis::Distributed::CannotDistribute
        names.each do |name|
          value = data_store.get_worker_payload(name)
          reportedly_working[name] = value unless value.nil? || value.empty?
        end
      end

      reportedly_working.keys.map do |key|
        worker = find(key.sub("worker:", ''), :skip_exists => true)
        worker.job = worker.decode(reportedly_working[key])
        worker
      end.compact
    end

    # Returns a single worker object. Accepts a string id.
    def self.find(worker_id, options = {})
      skip_exists = options[:skip_exists]

      if skip_exists || exists?(worker_id)
        host, pid, queues_raw = worker_id.split(':')
        queues = queues_raw.split(',')
        worker = new(*queues)
        worker.hostname = host
        worker.to_s = worker_id
        worker.pid = pid.to_i
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
      data_store.worker_exists?(worker_id)
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
    #
    # Workers should have `#prepare` called after they are initialized
    # if you are running work on the worker.
    def initialize(*queues)
      @shutdown = nil
      @paused = nil
      @before_first_fork_hook_ran = false

      verbose_value = ENV['LOGGING'] || ENV['VERBOSE']
      self.verbose = verbose_value if verbose_value
      self.very_verbose = ENV['VVERBOSE'] if ENV['VVERBOSE']
      self.pre_shutdown_timeout = (ENV['RESQUE_PRE_SHUTDOWN_TIMEOUT'] || 0.0).to_f
      self.term_timeout = (ENV['RESQUE_TERM_TIMEOUT'] || 4.0).to_f
      self.term_child = ENV['TERM_CHILD']
      self.graceful_term = ENV['GRACEFUL_TERM']
      self.run_at_exit_hooks = ENV['RUN_AT_EXIT_HOOKS']

      self.queues = queues
    end

    # Daemonizes the worker if ENV['BACKGROUND'] is set and writes
    # the process id to ENV['PIDFILE'] if set. Should only be called
    # once per worker.
    def prepare
      if ENV['BACKGROUND']
        unless Process.respond_to?('daemon')
            abort "env var BACKGROUND is set, which requires ruby >= 1.9"
        end
        Process.daemon(true)
      end

      if ENV['PIDFILE']
        File.open(ENV['PIDFILE'], 'w') { |f| f << pid }
      end

      self.reconnect if ENV['BACKGROUND']
    end

    def queues=(queues)
      queues = queues.empty? ? (ENV["QUEUES"] || ENV['QUEUE']).to_s.split(',') : queues
      @queues = queues.map { |queue| queue.to_s.strip }
      unless ['*', '?', '{', '}', '[', ']'].any? {|char| @queues.join.include?(char) }
        @static_queues = @queues.flatten.uniq
      end
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

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues.
    def queues
      return @static_queues if @static_queues
      @queues.map { |queue| glob_match(queue) }.flatten.uniq
    end

    def glob_match(pattern)
      Resque.queues.select do |queue|
        File.fnmatch?(pattern, queue)
      end.sort
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
      startup

      loop do
        break if shutdown?

        unless work_one_job(&block)
          break if interval.zero?
          log_with_severity :debug, "Sleeping for #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{queues.join(',')}"
          sleep interval
        end
      end

      unregister_worker
    rescue Exception => exception
      return if exception.class == SystemExit && !@child && run_at_exit_hooks
      log_with_severity :error, "Failed to start worker : #{exception.inspect}"
      unregister_worker(exception)
    end

    def work_one_job(job = nil, &block)
      return false if paused?
      return false unless job ||= reserve

      working_on job
      procline "Processing #{job.queue} since #{Time.now.to_i} [#{job.payload_class_name}]"

      log_with_severity :info, "got: #{job.inspect}"
      job.worker = self

      if fork_per_job?
        perform_with_fork(job, &block)
      else
        perform(job, &block)
      end

      done_working
      true
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

    # Reports the exception and marks the job as failed
    def report_failed_job(job,exception)
      log_with_severity :error, "#{job.inspect} failed: #{exception.inspect}"
      begin
        job.fail(exception)
      rescue Object => exception
        log_with_severity :error, "Received exception when reporting failure: #{exception.inspect}"
      end
      begin
        failed!
      rescue Object => exception
        log_with_severity :error, "Received exception when increasing failed jobs counter (redis issue) : #{exception.inspect}"
      end
    end


    # Processes a given job in the child.
    def perform(job)
      begin
        if fork_per_job?
          reconnect
          run_hook :after_fork, job
        end
        job.perform
      rescue Object => e
        report_failed_job(job,e)
      else
        log_with_severity :info, "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    def reserve
      queues.each do |queue|
        log_with_severity :debug, "Checking #{queue}"
        if job = Resque.reserve(queue)
          log_with_severity :debug, "Found job on #{queue}"
          return job
        end
      end

      nil
    rescue Exception => e
      log_with_severity :error, "Error reserving job: #{e.inspect}"
      log_with_severity :error, e.backtrace.join("\n")
      raise e
    end

    # Reconnect to Redis to avoid sharing a connection with the parent,
    # retry up to 3 times with increasing delay before giving up.
    def reconnect
      tries = 0
      begin
        data_store.reconnect
      rescue Redis::BaseConnectionError
        if (tries += 1) <= 3
          log_with_severity :error, "Error reconnecting to Redis; retrying"
          sleep(tries)
          retry
        else
          log_with_severity :error, "Error reconnecting to Redis; quitting"
          raise
        end
      end
    end

    # Runs all the methods needed when a worker begins its lifecycle.
    def startup
      $0 = "resque: Starting"

      enable_gc_optimizations
      register_signal_handlers
      start_heartbeat
      prune_dead_workers
      run_hook :before_first_fork
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
      trap('TERM') { graceful_term ? shutdown : shutdown!  }
      trap('INT')  { shutdown!  }

      begin
        trap('QUIT') { shutdown   }
        if term_child
          trap('USR1') { new_kill_child }
        else
          trap('USR1') { kill_child }
        end
        trap('USR2') { pause_processing }
        trap('CONT') { unpause_processing }
      rescue ArgumentError
        log_with_severity :warn, "Signals QUIT, USR1, USR2, and/or CONT not supported."
      end

      log_with_severity :debug, "Registered signals"
    end

    def unregister_signal_handlers
      trap('TERM') do
        trap('TERM') do
          # Ignore subsequent term signals
        end

        raise TermException.new("SIGTERM")
      end

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
      log_with_severity :info, 'Exiting...'
      @shutdown = true
    end

    # Kill the child and shutdown immediately.
    # If not forking, abort this process.
    def shutdown!
      shutdown
      if term_child
        if fork_per_job?
          new_kill_child
        else
          # Raise TermException in the same process
          trap('TERM') do
            # ignore subsequent terms
          end
          raise TermException.new("SIGTERM")
        end
      else
        kill_child
      end
    end

    # Should this worker shutdown as soon as current job is finished?
    def shutdown?
      @shutdown
    end

    # Kills the forked child immediately, without remorse. The job it
    # is processing will not be completed.
    def kill_child
      if @child
        log_with_severity :debug, "Killing child at #{@child}"
        if `ps -o pid,state -p #{@child}`
          Process.kill("KILL", @child) rescue nil
        else
          log_with_severity :debug, "Child #{@child} not found, restarting."
          shutdown
        end
      end
    end

    def heartbeat
      data_store.heartbeat(self)
    end

    def remove_heartbeat
      data_store.remove_heartbeat(self)
    end

    def heartbeat!(time = data_store.server_time)
      data_store.heartbeat!(self, time)
    end

    def self.all_heartbeats
      data_store.all_heartbeats
    end

    # Returns a list of workers that have sent a heartbeat in the past, but which
    # already expired (does NOT include workers that have never sent a heartbeat at all).
    def self.all_workers_with_expired_heartbeats
      workers = Worker.all
      heartbeats = Worker.all_heartbeats
      now = data_store.server_time

      workers.select do |worker|
        id = worker.to_s
        heartbeat = heartbeats[id]

        if heartbeat
          seconds_since_heartbeat = (now - Time.parse(heartbeat)).to_i
          seconds_since_heartbeat > Resque.prune_interval
        else
          false
        end
      end
    end

    def start_heartbeat
      remove_heartbeat

      @heartbeat_thread_signal = Resque::ThreadSignal.new

      @heartbeat_thread = Thread.new do
        loop do
          heartbeat!
          signaled = @heartbeat_thread_signal.wait_for_signal(Resque.heartbeat_interval)
          break if signaled
        end
      end

      @@all_heartbeat_threads << @heartbeat_thread
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait <term_timeout> seconds, and then a KILL signal if it has not quit
    # If pre_shutdown_timeout has been set to a positive number, it will allow
    # the child that many seconds before sending the aforementioned TERM and KILL.
    def new_kill_child
      if @child
        unless child_already_exited?
          if pre_shutdown_timeout && pre_shutdown_timeout > 0.0
            log_with_severity :debug, "Waiting #{pre_shutdown_timeout.to_f}s for child process to exit"
            return if wait_for_child_exit(pre_shutdown_timeout)
          end

          log_with_severity :debug, "Sending TERM signal to child #{@child}"
          Process.kill("TERM", @child)

          if wait_for_child_exit(term_timeout)
            return
          else
            log_with_severity :debug, "Sending KILL signal to child #{@child}"
            Process.kill("KILL", @child)
          end
        else
          log_with_severity :debug, "Child #{@child} already quit."
        end
      end
    rescue SystemCallError
      log_with_severity :error, "Child #{@child} already quit and reaped."
    end

    def child_already_exited?
      Process.waitpid(@child, Process::WNOHANG)
    end

    def wait_for_child_exit(timeout)
      (timeout * 10).round.times do |i|
        sleep(0.1)
        return true if child_already_exited?
      end
      false
    end

    # are we paused?
    def paused?
      @paused
    end

    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    def pause_processing
      log_with_severity :info, "USR2 received; pausing job processing"
      run_hook :before_pause, self
      @paused = true
    end

    # Start processing jobs again after a pause
    def unpause_processing
      log_with_severity :info, "CONT received; resuming job processing"
      @paused = false
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
      all_workers = Worker.all

      unless all_workers.empty?
        known_workers = worker_pids
        all_workers_with_expired_heartbeats = Worker.all_workers_with_expired_heartbeats
      end

      all_workers.each do |worker|
        # If the worker hasn't sent a heartbeat, remove it from the registry.
        #
        # If the worker hasn't ever sent a heartbeat, we won't remove it since
        # the first heartbeat is sent before the worker is registred it means
        # that this is a worker that doesn't support heartbeats, e.g., another
        # client library or an older version of Resque. We won't touch these.
        if all_workers_with_expired_heartbeats.include?(worker)
          log_with_severity :info, "Pruning dead worker: #{worker}"
          worker.unregister_worker(PruneDeadWorkerDirtyExit.new(worker.to_s))
          next
        end

        host, pid, worker_queues_raw = worker.id.split(':')
        worker_queues = worker_queues_raw.split(",")
        unless @queues.include?("*") || (worker_queues.to_set == @queues.to_set)
          # If the worker we are trying to prune does not belong to the queues
          # we are listening to, we should not touch it.
          # Attempt to prune a worker from different queues may easily result in
          # an unknown class exception, since that worker could easily be even
          # written in different language.
          next
        end

        next unless host == hostname
        next if known_workers.include?(pid)

        log_with_severity :debug, "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    # Registers ourself as a worker. Useful when entering the worker
    # lifecycle on startup.
    def register_worker
      data_store.register_worker(self)
    end

    # Runs a named hook, passing along any arguments.
    def run_hook(name, *args)
      return unless hooks = Resque.send(name)
      return if name == :before_first_fork && @before_first_fork_hook_ran
      msg = "Running #{name} hooks"
      msg << " with #{args.inspect}" if args.any?
      log_with_severity :info, msg

      hooks.each do |hook|
        args.any? ? hook.call(*args) : hook.call
        @before_first_fork_hook_ran = true if name == :before_first_fork
      end
    end

    def kill_background_threads
      if @heartbeat_thread
        @heartbeat_thread_signal.signal
        @heartbeat_thread.join
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
        begin
          job.fail(exception || DirtyExit.new("Job still being processed"))
        rescue RuntimeError => e
          log_with_severity :error, e.message
        end
      end

      kill_background_threads

      data_store.unregister_worker(self) do
        Stat.clear("processed:#{self}")
        Stat.clear("failed:#{self}")
      end
    rescue Exception => exception_while_unregistering
      message = exception_while_unregistering.message
      if exception
        message += "\nOriginal Exception (#{exception.class}): #{exception.message}"
        message += "\n  #{exception.backtrace.join("  \n")}" if exception.backtrace
      end
      fail(exception_while_unregistering.class,
           message,
           exception_while_unregistering.backtrace)
    end

    # Given a job, tells Redis we're working on it. Useful for seeing
    # what workers are doing and when.
    def working_on(job)
      data = encode \
        :queue   => job.queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => job.payload
      data_store.set_worker_payload(self,data)
    end

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    def done_working
      data_store.worker_done_working(self) do
        processed!
      end
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
      data_store.worker_start_time(self)
    end

    # Tell Redis we've started
    def started!
      data_store.worker_started(self)
    end

    # Returns a hash explaining the Job we're currently processing, if any.
    def job(reload = true)
      @job = nil if reload
      @job ||= decode(data_store.get_worker_payload(self)) || {}
    end
    attr_writer :job
    alias_method :processing, :job

    # Boolean - true if working, false if not
    def working?
      state == :working
    end

    # Boolean - true if idle, false if not
    def idle?
      state == :idle
    end

    def fork_per_job?
      return @fork_per_job if defined?(@fork_per_job)
      @fork_per_job = ENV["FORK_PER_JOB"] != 'false' && Kernel.respond_to?(:fork)
    end

    # Returns a symbol representing the current worker state,
    # which can be either :working or :idle
    def state
      data_store.get_worker_payload(self) ? :working : :idle
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

    # chomp'd hostname of this worker's machine
    def hostname
      @hostname ||= Socket.gethostname
    end

    # Returns Integer PID of running worker
    def pid
      @pid ||= Process.pid
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

    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    def windows_worker_pids
      tasklist_output = `tasklist /FI "IMAGENAME eq ruby.exe" /FO list`.encode("UTF-8", Encoding.locale_charmap)
      tasklist_output.split($/).select { |line| line =~ /^PID:/}.collect{ |line| line.gsub /PID:\s+/, '' }
    end

    # Find Resque worker pids on Linux and OS X.
    #
    def linux_worker_pids
      `ps -A -o pid,command | grep -E "[r]esque:work|[r]esque:\sStarting|[r]esque-[0-9]" | grep -v "resque-web"`.split("\n").map do |line|
        line.split(' ')[0]
      end
    end

    # Find Resque worker pids on Solaris.
    #
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    def solaris_worker_pids
      `ps -A -o pid,comm | grep "[r]uby" | grep -v "resque-web"`.split("\n").map do |line|
        real_pid = line.split(' ')[0]
        pargs_command = `pargs -a #{real_pid} 2>/dev/null | grep [r]esque | grep -v "resque-web"`
        if pargs_command.split(':')[1] == " resque-#{Resque::Version}"
          real_pid
        end
      end.compact
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   RESQUE_PROCLINE_PREFIXresque-VERSION: STRING
    def procline(string)
      $0 = "#{ENV['RESQUE_PROCLINE_PREFIX']}resque-#{Resque::Version}: #{string}"
      log_with_severity :debug, $0
    end

    def log(message)
      info(message)
    end

    def log!(message)
      debug(message)
    end


    def verbose
      @verbose
    end

    def very_verbose
      @very_verbose
    end

    def verbose=(value);
      if value && !very_verbose
        Resque.logger.formatter = VerboseFormatter.new
        Resque.logger.level = Logger::INFO
      elsif !value
        Resque.logger.formatter = QuietFormatter.new
      end

      @verbose = value
    end

    def very_verbose=(value)
      if value
        Resque.logger.formatter = VeryVerboseFormatter.new
        Resque.logger.level = Logger::DEBUG
      elsif !value && verbose
        Resque.logger.formatter = VerboseFormatter.new
        Resque.logger.level = Logger::INFO
      else
        Resque.logger.formatter = QuietFormatter.new
      end

      @very_verbose = value
    end

    private

    def perform_with_fork(job, &block)
      run_hook :before_fork, job

      begin
        @child = fork do
          unregister_signal_handlers if term_child
          perform(job, &block)
          exit! unless run_at_exit_hooks
        end
      rescue NotImplementedError
        @fork_per_job = false
        perform(job, &block)
        return
      end

      srand # Reseeding
      procline "Forked #{@child} at #{Time.now.to_i}"

      begin
        Process.waitpid(@child)
      rescue SystemCallError
        nil
      end

      job.fail(DirtyExit.new("Child process received unhandled signal #{$?.stopsig}", $?)) if $?.signaled?
      @child = nil
    end

    def log_with_severity(severity, message)
      Logging.log(severity, message)
    end
  end
end
