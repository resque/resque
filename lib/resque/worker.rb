class Resque
  class Worker
    attr_reader   :resque
    attr_accessor :logger

    def initialize(server, *queues)
      @resque = Resque.new(server)
      @queues = queues
      validate_queues
    end

    class NoQueueError < RuntimeError; end

    def validate_queues
      if @queues.nil? || @queues.empty?
        raise NoQueueError.new("Please give each worker at least one queue.")
      end
    end

    def work(interval = 5, &block)
      self.procline = "Starting"
      register_signal_handlers
      register_worker

      loop do
        break if @shutdown

        if job = reserve
          log "Got #{job.inspect}"
          self.procline = "Processing since #{Time.now.to_i}"
          process(job, &block)
        else
          break if interval.to_i == 0
          log "Sleeping"
          self.procline = "Waiting"
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
        job.fail(e, self)
        @resque.failed!(self)
      else
        log "#{job.inspect} done processing"
        job.done
      ensure
        yield job if block_given?
        done_working
      end
    end

    def register_signal_handlers
      trap('TERM') { shutdown }
      trap('INT')  { shutdown }
    end

    def shutdown
      log 'Exiting...'
      @shutdown = true
    end

    def reserve
      @queues.each do |queue|
        if job = @resque.reserve(queue)
          return job
        end
      end

      nil
    end

    def processed
      @resque.processed(self)
    end

    def failed
      @resque.failed(self)
    end

    def register_worker
      @resque.add_worker self
    end

    def unregister_worker
      @resque.remove_worker self
    end

    def working_on(job)
      @resque.set_worker_status(self, job.queue, job.payload)
    end

    def done_working
      @resque.clear_worker_status(self)
      @resque.processed!(self)
    end

    def inspect
      "#<Worker #{to_s}>"
    end

    def to_s
      @to_s ||= "#{`hostname`.chomp}:#{Process.pid}:#{@queues.join(',')}"
    end

    def log(message)
      puts "*** #{message}" if logger
    end

    def procline=(string)
      $0 = "resque: #{string}"
    end
  end
end
