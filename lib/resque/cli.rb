require "resque"

module Resque
  class CLI < Thor

    desc "work QUEUE", "Start processing jobs."

    method_option :pid,       :aliases => ["-p"], :type => :string
    method_option :interval,  :aliases => ["-i"], :type => :numeric, :default => 5
    method_option :deamon,    :aliases => ["-d"], :type => :boolean, :default => false
    method_option :timeout,   :aliases => ["-t"], :type => :numeric, :default => 4.0
    def work(queue = "*")
      queues = queue.to_s.split(',')

      worker = Resque::Worker.new(*queues)
      worker.term_timeout = options[:timeout]

      if options.has_key?(:deamon)
        Process.daemon(true)
      end

      if options.has_key?(:pid)
        File.open(options[:pid], 'w') { |f| f << worker.pid }
      end

      Resque.logger.info "Starting worker #{worker}"

      worker.work(options[:interval]) # interval, will block
    end
  end
end
