# require 'resque/tasks'
# will give you the resque tasks

namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => [ :preload, :setup ] do
    require 'resque'

    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')

    begin
      worker = Resque::Worker.new(*queues)
      if ENV['LOGGING'] || ENV['VERBOSE']
        worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      end
      if ENV['VVERBOSE']
        worker.very_verbose = ENV['VVERBOSE']
      end
      worker.term_timeout = ENV['RESQUE_TERM_TIMEOUT'] || 4.0
      worker.term_child = ENV['TERM_CHILD']
      worker.run_at_exit_hooks = ENV['RUN_AT_EXIT_HOOKS']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    if ENV['BACKGROUND']
      unless Process.respond_to?('daemon')
          abort "env var BACKGROUND is set, which requires ruby >= 1.9"
      end
      Process.daemon(true, true)
    end

    if ENV['PIDFILE']
      File.open(ENV['PIDFILE'], 'w') { |f| f << worker.pid }
    end

    worker.log "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end

  desc "Start multiple Resque workers. Should only be used in dev mode."
  task :workers do
    threads = []

    ENV['COUNT'].to_i.times do
      threads << Thread.new do
        system "rake resque:work"
      end
    end

    threads.each { |thread| thread.join }
  end

  # Preload app files if this is Rails
  task :preload => :setup do
    if defined?(Rails) && Rails.respond_to?(:application)
      # Rails 3
      Rails.application.eager_load!
    elsif defined?(Rails::Initializer)
      # Rails 2.3
      $rails_rake_task = false
      Rails::Initializer.run :load_application_classes
    end
  end

  namespace :failures do
    desc "Sort the 'failed' queue for the redis_multi_queue failure backend"
    task :sort do
      require 'resque'
      require 'resque/failure/redis'

      warn "Sorting #{Resque::Failure.count} failures..."
      Resque::Failure.each(0, Resque::Failure.count) do |_, failure|
        data = Resque.encode(failure)
        Resque.redis.rpush(Resque::Failure.failure_queue_name(failure['queue']), data)
      end
      warn "done!"
    end
  end
end
