require "resque"

module Resque
  class CLI < Thor

    desc "work", "Start processing jobs."
    option :queue,     :aliases => ["-q"], :type => :string,  :default => "*"
    option :require,   :aliases => ["-r"], :type => :string,  :default => "."
    option :pid,       :aliases => ["-p"], :type => :string
    option :interval,  :aliases => ["-i"], :type => :numeric, :default => 5
    option :deamon,    :aliases => ["-d"], :type => :boolean, :default => false
    option :timeout,   :aliases => ["-t"], :type => :numeric, :default => 4.0
    #option :verbose,   :aliases => ["-v"], :type => :boolean, :default => false
    #option :vverbose,  :aliases => ["-vv"], :type => :boolean, :default => false
    def work
      queues = options[:queue].to_s.split(',')

      load_enviroment(options[:require])
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

      def load_enviroment(file)
        if File.directory?(file)
          require "rails"
          require File.expand_path("#{file}/config/environment.rb")
          if defined?(::Rails) && ::Rails.respond_to?(:application)
            # Rails 3
            ::Rails.application.eager_load!
          elsif defined?(::Rails::Initializer)
            # Rails 2.3
            $rails_rake_task = false
            ::Rails::Initializer.run :load_application_classes
          end
        else
          require file
        end
      end
  end
end
