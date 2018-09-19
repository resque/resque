module Resque
  class Worker
    include Resque::Helpers
    extend Resque::Helpers
    include Resque::Logging

    attr_accessor :term_timeout, :jobs_per_fork, :worker_count, :thread_count
    attr_reader :jobs_processed
    attr_writer :hostname, :to_s, :pid

    @@all_heartbeat_threads = []
    def self.kill_all_heartbeat_threads
      @@all_heartbeat_threads.each(&:kill).each(&:join)
      @@all_heartbeat_threads = []
    end

    def data_store
      Resque.redis
    end

    def self.data_store
      Resque.redis
    end

    def encode(object)
      Resque.encode(object)
    end

    def decode(object)
      Resque.decode(object)
    end

    def self.all
      data_store.worker_ids.map { |id| find(id,true) }.compact
    end

    def self.working
      names = all
      return [] unless names.any?

      reportedly_working = data_store.workers_map(names).reject { |key, value|
        value.nil? || value.empty?
      }

      reportedly_working.keys.map { |key|
        worker = find(key.sub("worker:", ''), true)
        worker.job = worker.decode(reportedly_working[key])
        worker
      }.compact
    end

    def self.find(worker_id, known_to_exist = false)
      if known_to_exist || exists?(worker_id)
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

    def self.attach(worker_id)
      find(worker_id)
    end

    def self.exists?(worker_id)
      data_store.worker_exists?(worker_id)
    end

    def initialize(*queues)
      @shutdown = nil
      @paused = nil
      @before_first_fork_hook_ran = false

      @heartbeat_thread = nil
      @heartbeat_thread_signal = nil

      @worker_thread = nil

      verbose_value = ENV['LOGGING'] || ENV['VERBOSE']
      self.verbose = verbose_value if verbose_value
      self.very_verbose = ENV['VVERBOSE'] if ENV['VVERBOSE']
      self.term_timeout = (ENV['RESQUE_TERM_TIMEOUT'] || 30.0).to_f
      self.jobs_per_fork = [ (ENV['JOBS_PER_FORK'] || 1).to_i, 1 ].max
      self.worker_count = [ (ENV['WORKER_COUNT'] || 1).to_i, 1 ].max
      self.thread_count = [ (ENV['THREAD_COUNT'] || 1).to_i, 1 ].max

      self.queues = queues
    end

    def prepare
      if ENV['BACKGROUND']
        Process.daemon(true)
      end

      if ENV['PIDFILE']
        File.open(ENV['PIDFILE'], 'w') { |f| f << pid }
      end

      self.reconnect if ENV['BACKGROUND']
    end

    WILDCARDS = ['*', '?', '{', '}', '[', ']'].freeze

    def queues=(queues)
      queues = queues.empty? ? (ENV["QUEUES"] || ENV['QUEUE']).to_s.split(',') : queues
      @queues = queues.map { |queue| queue.to_s.strip }
      @has_dynamic_queues = WILDCARDS.any? {|char| @queues.join.include?(char) }
      validate_queues
    end

    def validate_queues
      if @queues.nil? || @queues.empty?
        raise NoQueueError.new("Please give each worker at least one queue.")
      end
    end

    def queues
      if @has_dynamic_queues
        current_queues = Resque.queues
        @queues.map { |queue| glob_match(current_queues, queue) }.flatten.uniq
      else
        @queues
      end
    end

    def glob_match(list, pattern)
      list.select do |queue|
        File.fnmatch?(pattern, queue)
      end.sort
    end

    def work(interval = 0.1, &block)
      interval = Float(interval)
      startup

      if !!ENV['DONT_FORK']
        worker_process(interval, &block)
      else
        @children = []
        (1..worker_count).map { fork_worker_process(interval, &block) }

        loop do
          break if shutdown?
          @children.each do |child|
            if Process.waitpid(child, Process::WNOHANG)
              @children.delete(child)
              break if interval.zero?
              fork_worker_process(interval, &block)
            end
          end

          break if interval.zero? and @children.size == 0
          sleep interval
        end
      end

      unregister_worker
    rescue Exception => exception
      return if exception.class == SystemExit && !@children
      log_with_severity :error, "Worker Error: #{exception.inspect}"
      unregister_worker(exception)
    end

    def fork_worker_process(interval, &block)
      @children << fork {
        if reconnect
          worker_process(interval, &block)
        end
        exit!
      }
      srand # Reseed after fork
      procline "Master Process.  Worker Children PIDs: #{@children.join(",")} Last Fork at #{Time.now.to_i}"
    end

    def worker_process(interval, &block)
      @mutex = Mutex.new
      @jobs_processed = 0
      @worker_threads = (1..thread_count).map { |i| WorkerThread.new(i, self, interval, &block) }
      @worker_threads.map(&:spawn).map(&:join)
    end

    def synchronize
      @mutex.synchronize do
        yield
      end
    end

    def job_processed
      synchronize do
        @jobs_processed += 1
      end
    end

    def set_procline
      jobs = @worker_threads.map { |thread| thread.payload_class_name }.compact
      if jobs.size > 0
        procline "Processing Job(s): #{jobs.join(", ")}"
      else
        procline paused? ? "Paused" : "Waiting for #{queues.join(',')}"
      end
    end

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

    def reconnect
      tries = 0
      begin
        data_store.reconnect
        true
      rescue Redis::BaseConnectionError
        if (tries += 1) <= 3
          log_with_severity :error, "Error reconnecting to Redis; retrying"
          sleep(tries)
          retry
        else
          log_with_severity :error, "Error reconnecting to Redis; quitting"
          false
        end
      end
    end

    def startup
      $0 = "resque: Starting"

      register_signal_handlers
      start_heartbeat
      prune_dead_workers
      register_worker

      $stdout.sync = true
    end

    def register_signal_handlers
      trap('TERM') { shutdown; send_child_signal('TERM'); kill_worker }
      trap('INT')  { shutdown; send_child_signal('INT'); kill_worker }

      begin
        trap('QUIT') { shutdown; send_child_signal('QUIT') }
        trap('USR1') { send_child_signal('USR1'); unpause_processing; kill_worker }
        trap('USR2') { pause_processing; send_child_signal('USR2') }
        trap('CONT') { unpause_processing; send_child_signal('CONT') }
      rescue ArgumentError
        log_with_severity :warn, "Signals QUIT, USR1, USR2, and/or CONT not supported."
      end

      log_with_severity :debug, "Registered signals"
    end

    def send_child_signal(signal)
      if @children
        @children.each do |child|
          Process.kill(signal, child) rescue nil
        end
      end
    end

    def kill_worker
      @worker_thread.kill if @worker_thread
    end

    def shutdown
      log_with_severity :info, 'Exiting...'
      @shutdown = true
    end

    def shutdown?
      @shutdown
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

    def paused?
      @paused
    end

    def pause_processing
      log_with_severity :info, "USR2 received; pausing job processing"
      @paused = true
    end

    def unpause_processing
      log_with_severity :info, "CONT received; resuming job processing"
      @paused = false
    end

    def prune_dead_workers
      return unless data_store.acquire_pruning_dead_worker_lock(self, Resque.heartbeat_interval)

      all_workers = Worker.all

      unless all_workers.empty?
        known_workers = worker_pids
        all_workers_with_expired_heartbeats = Worker.all_workers_with_expired_heartbeats
      end

      all_workers.each do |worker|
        if all_workers_with_expired_heartbeats.include?(worker)
          log_with_severity :info, "Pruning dead worker: #{worker}"
          worker.unregister_worker(PruneDeadWorkerDirtyExit.new(worker.to_s))
          next
        end

        host, pid, worker_queues_raw = worker.id.split(':')
        worker_queues = worker_queues_raw.split(",")
        unless @queues.include?("*") || (worker_queues.to_set == @queues.to_set)
          next
        end

        next unless host == hostname
        next if known_workers.include?(pid)

        log_with_severity :debug, "Pruning dead worker: #{worker}"
        worker.unregister_worker
      end
    end

    def register_worker
      data_store.register_worker(self)
    end

    def kill_background_threads
      if @heartbeat_thread
        @heartbeat_thread_signal.signal
        @heartbeat_thread.join
      end
    end

    def unregister_worker(exception = nil)
      if (hash = processing) && !hash.empty?
        job = Job.new(hash['queue'], hash['payload'])
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

    def processed
      Stat["processed:#{self}"]
    end

    def processed!
      Stat << "processed"
      Stat << "processed:#{self}"
    end

    def failed
      Stat["failed:#{self}"]
    end

    def failed!
      Stat << "failed"
      Stat << "failed:#{self}"
    end

    def started
      data_store.worker_start_time(self)
    end

    # Tell Redis we've started
    def started!
      data_store.worker_started(self)
    end

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
      tasklist_output.split($/).select { |line| line =~ /^PID:/ }.collect { |line| line.gsub(/PID:\s+/, '') }
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


    attr_reader :verbose, :very_verbose

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

    def log_with_severity(severity, message)
      Logging.log(severity, message)
    end
  end
end
