require 'redis'
require 'yajl'

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
    redis_push "queue:#{queue}", item
  end

  def pop(queue)
    redis_shift "queue:#{queue}"
  end

  def size(queue)
    redis_list_length "queue:#{queue}"
  end

  def peek(queue, start = 0, count = 1)
    redis_list_range "queue:#{queue}", start, count
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
  # jobs
  #

  def enqueue(queue, klass, *args)
    Job.create(queue, klass, *args)
  end

  def reserve(queue)
    Job.reserve(queue)
  end


  #
  # access to redis
  #

  def redis_push(list, value)
    redis.rpush list, encode(value)
  end

  def redis_shift(list)
    decode redis.lpop(list)
  end

  def redis_list_length(list)
    redis.llen(list).to_i
  end

  def redis_list_range(list, start = 0, count = 1)
    if count == 1
      decode redis.lindex(list, start)
    else
      Array(redis.lrange(list, start, start+count-1)).map do |item|
        decode item
      end
    end
  end

  def redis_set_member?(set, member)
    redis.sismember(set, member)
  end

  def redis_get(slot)
    redis.get slot
  end

  def redis_get_object(slot)
    decode redis.get(slot)
  end

  def redis_exists?(slot)
    redis.exists slot
  end


  #
  # workers
  #

  def workers
    Worker.all
  end

  def working
    names = workers
    return [] unless names.any?
    names = names.map { |name| "worker:#{name}" }
    redis.mapped_mget(*names).keys.map do |key|
      # cleanup
      key.sub("worker:", '')
    end
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
    redis.keys("*")
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
