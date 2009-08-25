module Resque
  class Worker
    attr_accessor :logger
    attr_writer   :to_s


    #
    # worker class methods
    #

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
      Resque.redis_set_member? :workers, worker_id
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
      register_signal_handlers
      register_worker

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
        Resque.failed! self
      else
        log "#{job.inspect} done processing"
      ensure
        yield job if block_given?
        done_working
      end
    end

    def reserve
      @queues.each do |queue|
        if job = Resque.reserve(queue)
          return job
        end
      end

      nil
    end


    #
    # startup / teardown
    #

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

    def register_worker
      Resque.add_worker self
    end

    def unregister_worker
      Resque.remove_worker self
    end

    def working_on(job)
      job.worker = self
      Resque.set_worker_status(self, job)
    end

    def done_working
      Resque.processed! self
      Resque.clear_worker_status self
    end


    #
    # query the worker
    #

    def processed
      Resque.stat_processed(self)
    end

    def failed
      Resque.stat_failed(self)
    end

    def started
      Resque.redis_get "worker:#{self}:started"
    end

    def job
      Resque.redis_get_object("worker:#{self}") || {}
    end
    alias_method :processing, :job

    def working?
      state == :working
    end

    def idle?
      state == :idle
    end

    def state
      Resque.redis_exists?("worker:#{self}") ? :working : :idle
    end

    def inspect
      "#<Worker #{to_s}>"
    end

    def to_s
      @to_s ||= "#{`hostname`.chomp}:#{Process.pid}:#{@queues.join(',')}"
    end


    #
    # randomness
    #

    def log(message)
      puts "*** #{message}" if logger
    end
  end
end
