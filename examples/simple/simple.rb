require 'resque'
require './my_job.rb'

# This queues a job, using the module in the my_job.rb file
# run 'redis-cli monitor' from the terminal
# to watch the job being queued
Resque.enqueue(MyJob)
puts "MyJob immediately queued for execution"
puts "Run "