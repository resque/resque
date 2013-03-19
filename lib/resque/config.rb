module Resque
  Config = Struct.new(:background, :count, :failure_backend, :fork_per_job,
                      :interval, :pid_file, :queues, :resque_term_timeout)

  @config = Config.new(
    ENV['BACKGROUND'],
    ENV['COUNT'],
    ENV['FAILURE_BACKEND'] || 'redis',
    ENV['FORK_PER_JOB'].nil? || ENV['FORK_PER_JOB'] == 'true',
    ENV['INTERVAL'] || 5,
    ENV['PID_FILE'],
    (ENV['QUEUES'] || ENV['QUEUE'] || '*').to_s.split(','),
    ENV['RESCUE_TERM_TIMEOUT'] || 4.0
  )

  def self.config
    yield @config if block_given?
    @config
  end
end
