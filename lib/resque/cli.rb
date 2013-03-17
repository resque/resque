require "resque"

module Resque
  class CLI < Thor
    class_option :config,    :aliases => ["-c"], :required => true

    desc "work QUEUE", "Start processing jobs."
    method_option :pid,       :aliases => ["-p"], :type => :string
    method_option :interval,  :aliases => ["-i"], :type => :numeric, :default => 5
    method_option :deamon,    :aliases => ["-d"], :type => :boolean, :default => false
    method_option :timeout,   :aliases => ["-t"], :type => :numeric, :default => 4.0
    method_option :verbose,   :aliases => ["-v"], :type => :boolean, :default => false
    method_option :vverbose,  :aliases => ["-vv"], :type => :boolean, :default => false
    def work(queue = "*")
      queues = queue.to_s.split(',')

      load_config(options[:config])
      worker_setup

      worker = Resque::Worker.new(*queues)

      worker.term_timeout = options[:timeout]
      #worker.verbose = options[:verbose]
      #worker.very_verbose = options[:vverbose]

      if options[:deamon]
        Process.daemon(true)
      end

      if options.has_key?(:pid)
        File.open(options[:pid], 'w') { |f| f << worker.pid }
      end

      Resque.logger.info "Starting worker #{worker}"

      worker.work(options[:interval]) # interval, will block
    end

    desc "kill WORKER", "Kills a worker"
    def kill(worker)
      pid = worker.split(':')[1].to_i

      begin
        Process.kill("KILL", pid)
        puts "killed #{worker}"
      rescue Errno::ESRCH
        puts "worker #{worker} not running"
      end

      remove(worker)
    end

    desc "remove WORKER", "Removes a worker"
    def remove(worker)
      Resque.remove_worker(worker)
      puts "Removed #{worker}"
    end

    desc "list", "Lists known workers"
    def list
      if Resque.workers.any?
        Resque.workers.each do |worker|
          puts "#{worker} (#{worker.state})"
        end
      else
        puts "None"
      end
    end

    protected

      def load_config(path)
        load(File.expand_path(path))
      end

      def worker_setup
        preload_rails_env
        Resque.config.worker_setup.call
      end

      def preload_rails_env
        if defined?(Rails) && Rails.respond_to?(:application)
          # Rails 3
          Rails.application.eager_load!
        elsif defined?(Rails::Initializer)
          # Rails 2.3
          $rails_rake_task = false
          Rails::Initializer.run :load_application_classes
        end
      end
  end
end
