# require 'resque/tasks'
# will give you the resque tasks


namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => [ :preload, :setup ] do
    require 'resque'

    begin
      worker = Resque::Worker.new
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    worker.prepare
    worker.log "Starting worker #{self}"
    worker.work(ENV['INTERVAL'] || 0.1) # interval, will block
  end

  desc "Start multiple Resque workers. Should only be used in dev mode."
  task :workers do
    threads = []

    if ENV['COUNT'].to_i < 1
      abort "set COUNT env var, e.g. $ COUNT=2 rake resque:workers"
    end

    ENV['COUNT'].to_i.times do
      threads << Thread.new do
        system "rake resque:work"
      end
    end

    threads.each { |thread| thread.join }
  end

  # Preload app files if this is Rails
  task :preload => :setup do
    if defined?(Rails)
      if Rails::VERSION::MAJOR > 3 && Rails.application.config.eager_load
        ActiveSupport.run_load_hooks(:before_eager_load, Rails.application)
        Rails.application.config.eager_load_namespaces.each(&:eager_load!)

      elsif Rails::VERSION::MAJOR == 3
        ActiveSupport.run_load_hooks(:before_eager_load, Rails.application)
        Rails.application.eager_load!

      elsif defined?(Rails::Initializer)
        $rails_rake_task = false
        Rails::Initializer.run :load_application_classes
      end
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
