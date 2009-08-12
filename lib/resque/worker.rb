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

    def work(interval = 5)
      register_signal_handlers
      register_worker

      loop do
        break if @shutdown

        if job = reserve
          log "Got #{job.inspect}"
          process job
        else
          log "Sleeping"
          sleep interval.to_i
        end
      end

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
      else
        log "#{job.inspect} done processing"
        job.done
      ensure
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

    def register_worker
      @resque.add_worker self
    end

    def unregister_worker
      @resque.remove_worker self
    end

    def working_on(job)
      @resque.set_worker_status(self, job.payload)
    end

    def done_working
      @resque.set_worker_status(self, nil)
    end

    def inspect
      "#<Worker #{to_s}>"
    end

    def to_s
      @to_s ||= "#{`hostname`.chomp}:#{Process.pid}"
    end

    def log(message)
      puts "*** #{message}" if logger
    end
  end
end
