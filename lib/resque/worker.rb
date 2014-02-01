require 'time'
require 'set'

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

    def redis
      Resque.redis
    end

    def self.redis
      Resque.redis
    end

    # Given a Ruby object, returns a string suitable for storage in a
    # queue.
    def encode(object)
      if MultiJson.respond_to?(:dump) && MultiJson.respond_to?(:load)
        MultiJson.dump object
      else
        MultiJson.encode object
      end
    end

    # Given a string, returns a Ruby object.
    def decode(object)
      return unless object

      begin
        if MultiJson.respond_to?(:dump) && MultiJson.respond_to?(:load)
          MultiJson.load object
        else
          MultiJson.decode object
        end
      rescue ::MultiJson::DecodeError => e
        raise DecodeException, e.message, e.backtrace
      end
    end

    # Boolean indicating whether this worker can or can not fork.
    # Automatically set if a fork(2) fails.
    attr_accessor :cant_fork

    attr_accessor :term_timeout

    # decide whether to use new_kill_child logic
    attr_accessor :term_child

    # When set to true, forked workers will exit with `exit`, calling any `at_exit` code handlers that have been
    # registered in the application. Otherwise, forked workers exit with `exit!`
    attr_accessor :run_at_exit_hooks

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

        if not paused? and job = reserve
          log "got: #{job.inspect}"
          job.worker = self
          working_on job

          procline "Processing #{job.queue} since #{Time.now.to_i} [#{job.payload_class_name}]"
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
            unregister_signal_handlers if will_fork? && term_child
            begin

              reconnect
              perform(job, &block)

            rescue Exception => exception
              report_failed_job(job,exception)
            end

            if will_fork?
              run_at_exit_hooks ? exit : exit!
            end
          end

          done_working
          @child = nil
        else
          break if interval.zero?
          log! "Sleeping for #{interval} seconds"
          procline paused? ? "Paused" : "Waiting for #{@queues.join(',')}"
          sleep interval
        end
      end

      unregister_worker
    rescue Exception => exception
      unless exception.class == SystemExit && !@child && run_at_exit_hooks
        log "Failed to start worker : #{exception.inspect}"

        unregister_worker(exception)
      end
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
      log "#{job.inspect} failed: #{exception.inspect}"
      begin
        job.fail(exception)
      rescue Object => exception
        log "Received exception when reporting failure: #{exception.inspect}"
      end
      begin
        failed!
      rescue Object => exception
        log "Received exception when increasing failed jobs counter (redis issue) : #{exception.inspect}"
      end
    end

    # Processes a given job in the child.
    def perform(job)
      begin
        run_hook :after_fork, job if will_fork?
        job.perform
      rescue Object => e
        report_failed_job(job,e)
      else
        log "done: #{job.inspect}"
      ensure
        yield job if block_given?
      end
    end

    # Attempts to grab a job off one of the provided queues. Returns
    # nil if no job can be found.
    def reserve
      queues.each do |queue|
        log! "Checking #{queue}"
        if job = Resque.reserve(queue)
          log! "Found job on #{queue}"
          return job
        end
      end

      nil
    rescue Exception => e
      log "Error reserving job: #{e.inspect}"
      log e.backtrace.join("\n")
      raise e
    end

    # Reconnect to Redis to avoid sharing a connection with the parent,
    # retry up to 3 times with increasing delay before giving up.
    def reconnect
      tries = 0
      begin
        redis.client.reconnect
      rescue Redis::BaseConnectionError
        if (tries += 1) <= 3
          log "Error reconnecting to Redis; retrying"
          sleep(tries)
          retry
        else
          log "Error reconnecting to Redis; quitting"
          raise
        end
      end
    end

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues.
    def queues
      @queues.map do |queue|
        queue.strip!
        if (matched_queues = glob_match(queue)).empty?
          queue
        else
          matched_queues
        end
      end.flatten.uniq
    end

    def glob_match(pattern)
      Resque.queues.select do |queue|
        File.fnmatch?(pattern, queue)
      end.sort
    end

    # Not every platform supports fork. Here we do our magic to
    # determine if yours does.
    def fork(job)
      return if @cant_fork

      # Only run before_fork hooks if we're actually going to fork
      # (after checking @cant_fork)
      run_hook :before_fork, job

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
      Kernel.warn "WARNING: This way of doing signal handling is now deprecated. Please see http://hone.heroku.com/resque/2012/08/21/resque-signals.html for more info." unless term_child or $TESTING
      enable_gc_optimizations
      register_signal_handlers
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
      trap('TERM') { shutdown!  }
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
        warn "Signals QUIT, USR1, USR2, and/or CONT not supported."
      end

      log! "Registered signals"
    end

    def unregister_signal_handlers
      trap('TERM') do
        trap ('TERM') do 
          # ignore subsequent terms               
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
      log 'Exiting...'
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
        log! "Killing child at #{@child}"
        if `ps -o pid,state -p #{@child}`
          Process.kill("KILL", @child) rescue nil
        else
          log! "Child #{@child} not found, restarting."
          shutdown
        end
      end
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait 5 seconds, and then a KILL signal if it has not quit
    def new_kill_child
      if @child
        unless Process.waitpid(@child, Process::WNOHANG)
          log! "Sending TERM signal to child #{@child}"
          Process.kill("TERM", @child)
          (term_timeout.to_f * 10).round.times do |i|
            sleep(0.1)
            return if Process.waitpid(@child, Process::WNOHANG)
          end
          log! "Sending KILL signal to child #{@child}"
          Process.kill("KILL", @child)
        else
          log! "Child #{@child} already quit."
        end
      end
    rescue SystemCallError
      log! "Child #{@child} already quit and reaped."
    end

    # are we paused?
    def paused?
      @paused
    end

    # Stop processing jobs after the current one has completed (if we're
    # currently running one).
    def pause_processing
      log "USR2 received; pausing job processing"
      @paused = true
    end

    # Start processing jobs again after a pause
    def unpause_processing
      log "CONT received; resuming job processing"
      @paused = false
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
        log! "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    # Registers ourself as a worker. Useful when entering the worker
    # lifecycle on startup.
    def register_worker
      redis.pipelined do
        redis.sadd(:workers, self)
        started!
      end
    end

    # Runs a named hook, passing along any arguments.
    def run_hook(name, *args)
      return unless hooks = Resque.send(name)
      msg = "Running #{name} hooks"
      msg << " with #{args.inspect}" if args.any?
      log msg

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

      redis.pipelined do
        redis.srem(:workers, self)
        redis.del("worker:#{self}")
        redis.del("worker:#{self}:started")

        Stat.clear("processed:#{self}")
        Stat.clear("failed:#{self}")
      end
    end

    # Given a job, tells Redis we're working on it. Useful for seeing
    # what workers are doing and when.
    def working_on(job)
      data = encode \
        :queue   => job.queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => job.payload
      redis.set("worker:#{self}", data)
    end

    # Called when we are done working - clears our `working_on` state
    # and tells Redis we processed a job.
    def done_working
      redis.pipelined do
        processed!
        redis.del("worker:#{self}")
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
      redis.get "worker:#{self}:started"
    end

    # Tell Redis we've started
    def started!
      redis.set("worker:#{self}:started", Time.now.to_s)
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
      !@cant_fork && !$TESTING && fork_per_job?
    end

    def fork_per_job?
      ENV["FORK_PER_JOB"] != 'false'
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
      @to_s ||= "#{hostname}:#{pid}:#{@queues.join(',')}"
    end
    alias_method :id, :to_s

    # chomp'd hostname of this machine
    def hostname
      Socket.gethostname
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
      `ps -A -o pid,command | grep "[r]esque" | grep -v "resque-web"`.split("\n").map do |line|
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
    #   resque-VERSION: STRING
    def procline(string)
      $0 = "resque-#{Resque::Version}: #{string}"
      log! $0
    end

    # Log a message to Resque.logger
    # can't use alias_method since info/debug are private methods
    def log(message)
      info(message)
    end

    def log!(message)
      debug(message)
    end

    # Deprecated legacy methods for controlling the logging threshhold
    # Use Resque.logger.level now, e.g.:
    #
    #     Resque.logger.level = Logger::DEBUG
    #
    def verbose
      logger_severity_deprecation_warning
      @verbose
    end

    def very_verbose
      logger_severity_deprecation_warning
      @very_verbose
    end

    def verbose=(value);
      logger_severity_deprecation_warning

      if value && !very_verbose
        Resque.logger.formatter = VerboseFormatter.new
      elsif !value
        Resque.logger.formatter = QuietFormatter.new
      end

      @verbose = value
    end

    def very_verbose=(value)
      logger_severity_deprecation_warning
      if value
        Resque.logger.formatter = VeryVerboseFormatter.new
      elsif !value && verbose
        Resque.logger.formatter = VerboseFormatter.new
      else
        Resque.logger.formatter = QuietFormatter.new
      end

      @very_verbose = value
    end

    def logger_severity_deprecation_warning
      return if $TESTING
      return if $warned_logger_severity_deprecation
      Kernel.warn "*** DEPRECATION WARNING: Resque::Worker#verbose and #very_verbose are deprecated. Please set Resque.logger.level instead"
      Kernel.warn "Called from: #{caller[0..5].join("\n\t")}"
      $warned_logger_severity_deprecation = true
      nil
    end
  end
end
