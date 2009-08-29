require 'redis'
require 'yajl'

require 'resque/failure'
require 'resque/failure/base'

require 'resque/stat'
require 'resque/job'
require 'resque/worker'

module Resque
  extend self

  #
  # We need a Redis server to connect to
  #

  def redis=(server)
    case server
    when String
      host, port = server.split(':')
      @redis = Redis.new(:host => host, :port => port, :namespace => :resque)
    when Redis
      @redis = server
    else
      raise "I don't know what to do with #{server.inspect}"
    end
  end

  def redis
    @redis ||= Redis.new(:host => 'localhost', :port => 6379, :namespace => :resque)
  end

  def to_s
    "Resque Client connected to #{redis.server}"
  end


  #
  # queue manipulation
  #

  def push(queue, item)
    watch_queue(queue)
    redis.rpush "queue:#{queue}", encode(item)
  end

  def pop(queue)
    decode redis.lpop("queue:#{queue}")
  end

  def size(queue)
    redis.llen("queue:#{queue}").to_i
  end

  def peek(queue, start = 0, count = 1)
    list_range("queue:#{queue}", start, count)
  end

  # Also used by Resque::Job for access to the `failed` faux-queue
  # (for now)
  def list_range(key, start = 0, count = 1)
    if count == 1
      decode redis.lindex(key, start)
    else
      Array(redis.lrange(key, start, start+count-1)).map do |item|
        decode item
      end
    end
  end

  def queues
    redis.smembers(:queues)
  end

  # Used internally to keep track of which queues
  # we've created.
  def watch_queue(queue)
    @watched_queues ||= {}
    return if @watched_queues[queue]
    redis.sadd(:queues, queue.to_s)
  end


  #
  # job shortcuts
  #

  def enqueue(queue, klass, *args)
    Job.create(queue, klass, *args)
  end

  def reserve(queue)
    Job.reserve(queue)
  end

  #
  # worker shortcuts
  #

  def workers
    Worker.all
  end

  def working
    Worker.working
  end


  #
  # stats
  #

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

  def keys
    redis.keys("*").map do |key|
      key.sub('resque:', '')
    end
  end


  #
  # encoding / decoding
  #

  def encode(object)
    Yajl::Encoder.encode(object)
  end

  def decode(object)
    Yajl::Parser.parse(object) if object
  end
end
