namespace :jobs do
  desc "Start a Resque Ranger"
  task :work => [ :environment, :setup ] do
    queues = ENV['QUEUE'].split(',')
    worker = Resque::Worker.new('localhost:6379', *queues)

    puts "*** Starting worker #{worker} for #{ENV['QUEUE']}"

    worker.work(5) # interval, will block
  end

  task :setup do
    Grit::Git.git_timeout = 10.minutes
  end
end
