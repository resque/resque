require 'redis'
require 'yajl'

require 'resque/job'
require 'resque/worker'

class Resque
  attr_reader :redis

  def initialize(server)
    host, port = server.split(':')
    @redis = Redis.new(:host => host, :port => port)
  end


  #
  # queue manipulation
  #

  def push(queue, item)
    @redis.rpush(key(queue), encode(item))
  end

  def pop(queue)
    decode @redis.lpop(key(queue))
  end

  def size(queue)
    @redis.llen(key(queue))
  end

  def peek(queue, start = 0, count = 1)
    if count == 1
      decode @redis.lindex(key(queue), start)
    else
      Array(@redis.lrange(key(queue), start, start+count-1)).map do |item|
        decode item
      end
    end
  end


  #
  # jobs.
  #

  def enqueue(queue, klass, *args)
    push(queue, :class => klass.to_s, :args => args)
  end

  def reserve(queue)
    return unless payload = pop(queue)
    Job.new(self, queue, payload)
  end

  def add_worker(worker)
    @redis.sadd(key(:workers), worker.to_s)
  end

  def remove_worker(worker)
    @redis.srem(key(:workers), worker.to_s)
  end

  def workers
    @redis.smembers(key(:workers))
  end

  def worker(id)
    decode @redis.get(key(:worker, id.to_s))
  end

  def worker_state(id)
    if @redis.exists(key(:worker, id))
      :working
    else
      :idle
    end
  end

  def set_worker_status(id, payload = nil)
    if payload
      @redis.set(key(:worker, id.to_s), encode(:run_at => Time.now, :payload => payload))
    else
      @redis.del(key(:worker, id.to_s))
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

  #
  # namespacing
  #

  def key(*queue)
    "resque:#{queue.join(':')}"
  end
end
