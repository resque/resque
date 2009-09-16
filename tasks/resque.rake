namespace :resque do
  desc "Start a Resque Ranger"
  task :work do
    Rake::Task['resque:setup'].invoke rescue nil

    worker = nil
    queues = (ENV['QUEUES'] || ENV['QUEUE']).to_s.split(',')

    begin
      worker = Resque::Worker.new(*queues)
      worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
      worker.very_verbose = ENV['VVERBOSE']
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    puts "*** Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
end
