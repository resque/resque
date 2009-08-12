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
    end

    def process(job = nil)
      return unless job ||= reserve

      begin
        job.perform
      rescue Object => e
        log "#{job.inspect} failed: #{e.inspect}"
        job.fail(e, self)
      else
        log "#{job.inspect} done processing"
        job.done
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
