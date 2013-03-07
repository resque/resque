# Run resque to work on all queues via
# rake resque:work QUEUE='*'

require "resque/tasks"

task "resque:setup" => :environment
