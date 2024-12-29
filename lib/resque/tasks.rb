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
    worker.log "Starting worker #{worker}"
    worker.work(ENV['INTERVAL'] || 5) # interval, will block
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

  # Defined for backwards compatibility.
  task :preload => :setup

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
