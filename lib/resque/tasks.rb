# require 'resque/tasks'
# will give you the resque tasks

namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => :setup do
    require 'resque'

    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')

    begin
      worker = Resque::Worker.new(*queues)
      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
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
end
