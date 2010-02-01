require 'redis/namespace'

begin
  require 'yajl'
rescue LoadError
  require 'json'
end

require 'resque/errors'

require 'resque/failure'
require 'resque/failure/base'

require 'resque/helpers'
require 'resque/stat'
require 'resque/job'
require 'resque/worker'

module Resque
  include Helpers
  extend self

  # Accepts a 'hostname:port' string or a Redis server.
  def redis=(server)
    case server
    when String
      host, port, dbid = server.split(':')
      redis = Redis.new(:host => host, :port => port, :thread_safe => true, :db=>dbid || 0)
      @redis = Redis::Namespace.new(:resque, :redis => redis)
    when Redis
      @redis = Redis::Namespace.new(:resque, :redis => server)
    else
      raise "I don't know what to do with #{server.inspect}"
    end
  end

  # Returns the current Redis connection. If none has been created, will
  # create a new one.
  def redis
    return @redis if @redis
    self.redis = 'localhost:6379'
    self.redis
  end

  def to_s
    "Resque Client connected to #{redis.server}"
  end


  #
  # queue manipulation
  #

  # Pushes a job onto a queue. Queue name should be a string and the
  # item should be any JSON-able Ruby object.
  def push(queue, item)
    watch_queue(queue)
    redis.rpush "queue:#{queue}", encode(item)
  end

  # Pops a job off a queue. Queue name should be a string.
  #
  # Returns a Ruby object.
  def pop(queue)
    decode redis.lpop("queue:#{queue}")
  end

  # Returns an int representing the size of a queue.
  # Queue name should be a string.
  def size(queue)
    redis.llen("queue:#{queue}").to_i
  end

  # Returns an array of items currently queued. Queue name should be
  # a string.
  #
  # start and count should be integer and can be used for pagination.
  # start is the item to begin, count is how many items to return.
  #
  # To get the 3rd page of a 30 item, paginatied list one would use:
  #   Resque.peek('my_list', 59, 30)
  def peek(queue, start = 0, count = 1)
    list_range("queue:#{queue}", start, count)
  end

  # Does the dirty work of fetching a range of items from a Redis list
  # and converting them into Ruby objects.
  def list_range(key, start = 0, count = 1)
    if count == 1
      decode redis.lindex(key, start)
    else
      Array(redis.lrange(key, start, start+count-1)).map do |item|
        decode item
      end
    end
  end

  # Returns an array of all known Resque queues as strings.
  def queues
    redis.smembers(:queues)
  end

  # Given a queue name, completely deletes the queue.
  def remove_queue(queue)
    redis.srem(:queues, queue.to_s)
    redis.del("queue:#{queue}")
  end

  # Used internally to keep track of which queues we've created.
  # Don't call this directly.
  def watch_queue(queue)
    redis.sadd(:queues, queue.to_s)
  end


  #
  # job shortcuts
  #

  # This method can be used to conveniently add a job to a queue.
  # It assumes the class you're passing it is a real Ruby class (not
  # a string or reference) which either:
  #
  #   a) has a @queue ivar set
  #   b) responds to `queue`
  #
  # If either of those conditions are met, it will use the value obtained
  # from performing one of the above operations to determine the queue.
  #
  # If no queue can be inferred this method will return a non-true value.
  #
  # This method is considered part of the `stable` API.
  def enqueue(klass, *args)
    queue = klass.instance_variable_get(:@queue)
    queue ||= klass.queue if klass.respond_to?(:queue)
    Job.create(queue, klass, *args)
  end

  # This method will return a `Resque::Job` object or a non-true value
  # depending on whether a job can be obtained. You should pass it the
  # precise name of a queue: case matters.
  #
  # This method is considered part of the `stable` API.
  def reserve(queue)
    Job.reserve(queue)
  end


  #
  # worker shortcuts
  #

  # A shortcut to Worker.all
  def workers
    Worker.all
  end

  # A shortcut to Worker.working
  def working
    Worker.working
  end


  #
  # stats
  #

  # Returns a hash, similar to redis-rb's #info, of interesting stats.
  def info
    return {
      :pending   => queues.inject(0) { |m,k| m + size(k) },
      :processed => Stat[:processed],
      :queues    => queues.size,
      :workers   => workers.size.to_i,
      :working   => working.size,
      :failed    => Stat[:failed],
      :servers   => [redis.server]
    }
  end

  # Returns an array of all known Resque keys in Redis. Redis' KEYS operation
  # is O(N) for the keyspace, so be careful - this can be slow for big databases.
  def keys
    redis.keys("*").map do |key|
      key.sub('resque:', '')
    end
  end
end
