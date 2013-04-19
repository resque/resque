require 'yaml'
require 'thor'
require "resque"

module Resque
  class CLI < Thor
    class_option :config,    :aliases => ["-c"], :type => :string
    class_option :redis,     :aliases => ["-R"], :type => :string

    def initialize(args = [], opts = [], config = {})
      super(args, opts, config)

      if options[:config] && File.exists?(options[:config])
        @options = YAML.load_file(options[:config]).symbolize_keys.merge(@options.symbolize_keys)
      end

      Resque.redis = options[:redis]
    end

    desc "work", "Start processing jobs."
    option :queues,       :aliases => ["-q"], :type => :string
    option :require,      :aliases => ["-r"], :type => :string
    option :pid_file,     :aliases => ["-p"], :type => :string
    option :interval,     :aliases => ["-i"], :type => :numeric
    option :daemon,       :aliases => ["-d"], :type => :boolean
    option :timeout,      :aliases => ["-t"], :type => :numeric
    def work
      load_enviroment(options[:require])

      queues = options[:queues].to_s.split(',')
      opts = @options.symbolize_keys.slice(:timeout, :interval, :daemon, :pid_file)

      Resque::Worker.new(queues, opts).work
    end

    desc "workers", "Start multiple Resque workers. Should only be used in dev mode."
    option :count, :aliases => ["-n"], :type => :numeric, :default => 5
    def workers
      threads = []

      options[:count].to_i.times do
        threads << Thread.new do
          self.work
        end
      end

      threads.each(&:join)
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
      Resque::WorkerRegistry.remove(worker)
      puts "removed #{worker}"
    end

    desc "list", "Lists known workers"
    def list
      workers = Resque::WorkerRegistry.all
      if workers.any?
        workers.each do |worker|
          puts "#{worker} (#{worker.state})"
        end
      else
        puts "None"
      end
    end

    desc "sort_failures", "Sort the 'failed' queue for the redis_multi_queue failure backend"
    def sort_failures
      require 'resque/failure/redis'

      warn "Sorting #{Resque::Failure.count} failures..."
      Resque::Failure.each(0, Resque::Failure.count) do |_, failure|
        data = Resque.encode(failure)
        Resque.backend.store.rpush(Resque::Failure.failure_queue_name(failure['queue']), data)
      end
      warn "done!"
    end


    protected

      def load_enviroment(file = nil)
        file ||= "."

        if File.directory?(file) && File.exists?(File.expand_path("#{file}/config/environment.rb"))
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
        elsif File.file?(file)
          require File.expand_path(file)
        end
      end

  end
end
