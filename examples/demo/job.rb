require 'resque'

module Demo
  module Job
    @queue = :default

    def self.perform(params)
      sleep 1
      puts "Processed a job!"
    end
  end
end
