module MyJob
	# Sets the default queue
  @queue = :default

  # This is the code executed when the job is ran by the worker
  def self.perform
    sleep 10
    puts "You can see this run in the \'redis-cli monitor\' console!"
  end
end