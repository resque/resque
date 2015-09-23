class LongRunningJob
  @queue = :long_running_job

  def self.perform( sleep_time, rescue_time=nil )
    Resque.redis.client.reconnect # get its own connection
    Resque.redis.rpush( 'sigterm-test:start', Process.pid )
    sleep sleep_time
    Resque.redis.rpush( 'sigterm-test:result', 'Finished Normally' )
  rescue Resque::TermException => e
    Resque.redis.rpush( 'sigterm-test:result', %Q(Caught TermException: #{e.inspect}))
    sleep rescue_time
  ensure
    Resque.redis.rpush( 'sigterm-test:ensure_block_executed', 'exiting.' )
  end
end
