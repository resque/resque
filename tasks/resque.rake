namespace :resque do
  desc "Start a Resque Ranger"
  task :work do
    Rake::Task['resque:setup'].invoke rescue nil

    queues = ENV['QUEUE'].to_s.split(',')
    worker = Resque::Worker.new('localhost:6379', *queues)

    puts "*** Starting worker #{worker} for #{ENV['QUEUE']}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
end
