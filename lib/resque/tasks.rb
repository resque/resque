# require 'resque/tasks'
# will give you the resque tasks

namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => :setup do
    require 'resque'

    worker = nil
    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')
    backup_queue = ENV['BACKUP_QUEUE']

    begin
      worker = Resque::Worker.new(*queues, :backup_queue => backup_queue)
      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    worker.log "Starting worker #{worker}"
    worker.log "Worker has backup_queue name: #{backup_queue}" if backup_queue

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
