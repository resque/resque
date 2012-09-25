# require 'resque/tasks'
# will give you the resque tasks

namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => [:pidfile, :setup] do
    require 'resque'

    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')

    begin
      worker = Resque::Worker.new(*queues)
      worker.verbose      = (ENV['LOGGING'] || ENV['VERBOSE'])
      worker.very_verbose = ENV['VVERBOSE']
      worker.term_timeout = (ENV['RESQUE_TERM_TIMEOUT'] || 4.0)
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    if ENV['BACKGROUND']
      unless Process.respond_to?('daemon')
        abort "env var BACKGROUND is set, which requires ruby >= 1.9"
      end

      Process.daemon(true)
    end

    worker.log "Starting worker #{worker}"

    # interval, will block
    worker.work(ENV['INTERVAL'] || 5)
  end

  desc "Start multiple Resque workers. Should only be used in dev mode."
  task :workers do
    threads = Array.new(ENV['COUNT'].to_i) do
      Thread.new { system "rake resque:work" }
    end

    threads.each { |thread| thread.join }
  end
end
