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
