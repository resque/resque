class Resque
  class Worker
    attr_reader :resque

    def initialize(server, *queues)
      @resque = Resque.new(server)
      @queues = queues
    end

    def work(interval = 5)
      register_signal_handlers

      loop do
        break if @shutdown

        if job = reserve
          process job
        else
          sleep interval.to_i
        end
      end
    end

    def process(job = nil)
      return unless job ||= reserve

      begin
        job.perform
      rescue Object => e
        job.fail(e, self)
      else
        job.done
      end
    end

    def register_signal_handlers
      trap('TERM') { shutdown }
      trap('INT')  { shutdown }
    end

    def shutdown
      puts 'Exiting...'
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
      @to_s ||= "#{Process.pid}:#{`hostname`.chomp}"
    end
  end
end
