require 'dist_redis'
require 'yajl'

require 'resque/job'
require 'resque/worker'

class Resque
  attr_reader :redis

  def self.redis=(servers)
    case servers
    when String, Array
      @redis = DistRedis.new(:hosts => Array(servers))
    when Redis
      @redis = servers
    else
      raise "I don't know what to do with #{servers.inspect}"
    end
  end

  def self.redis
    @redis ||= DistRedis.new(:hosts => ['localhost:6379'])
  end

  def initialize(servers = nil)
    Resque.redis = servers if servers
    @redis = Resque.redis
  end

  def to_s
    "Resque Client connected to #{@redis.server}"
  end


  #
  # queue manipulation
  #

  def push(queue, item)
    watch_queue(queue)
    @redis.rpush(key(:queue, queue), encode(item))
  end

  def pop(queue)
    decode @redis.lpop(key(:queue, queue))
  end

  def size(queue)
    @redis.llen(key(:queue, queue))
  end

  def peek(queue, start = 0, count = 1)
    if count == 1
      decode @redis.lindex(key(:queue, queue), start)
    else
      Array(@redis.lrange(key(:queue, queue), start, start+count-1)).map do |item|
        decode item
      end
    end
  end

  def queues
    @redis.smembers(key(:queues))
  end

  # Used internally to keep track of which queues
  # we've created.
  def watch_queue(queue)
    @watched_queues ||= {}
    return if @watched_queues[queue]
    @redis.sadd(key(:queues), queue.to_s)
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

  def fail(payload, exception, worker, queue)
    @redis.rpush key(:failed), encode(
      :failed_at => Time.now.to_s,
      :payload   => payload,
      :error     => exception.to_s,
      :backtrace => exception.backtrace,
      :worker    => worker,
      :queue     => queue)
  end

  def failed_size
    @redis.llen(key(:failed)).to_i
  end

  def failed(start = 0, count = 1)
    if count == 1
      decode @redis.lindex(key(:failed), start)
    else
      Array(@redis.lrange(key(:failed), start, start+count-1)).map do |item|
        decode item
      end
    end
  end


  #
  # workers
  #

  def add_worker(worker)
    @redis.pipelined do |redis|
      redis.sadd(key(:workers), worker.to_s)
      redis.set(key(:worker, worker.to_s, :started), Time.now.to_s)
    end
  end

  def remove_worker(worker)
    @redis.pipelined do |redis|
      clear_processed_for worker, redis
      clear_failed_for worker, redis
      clear_worker_status worker, redis
      redis.del(key(:worker, worker.to_s, :started))
      redis.srem(key(:workers), worker.to_s)
    end
  end

  def workers
    @redis.smembers(key(:workers))
  end

  def worker(id)
    decode @redis.get(key(:worker, id.to_s))
  end

  def worker?(id)
    @redis.sismember(key(:workers), id.to_s)
  end

  def working
    names = workers
    return [] unless names.any?
    names = names.map { |name| key(:worker, name) }
    @redis.mapped_mget(*names).keys.map do |key|
      # cleanup
      key.sub(key(:worker) + ':', '')
    end
  end

  def worker_started(id)
    @redis.get(key(:worker, id.to_s, :started))
  end

  def worker_state(id)
    @redis.exists(key(:worker, id)) ? :working : :idle
  end

  def set_worker_status(id, queue, payload)
    data = encode \
      :queue   => queue,
      :run_at  => Time.now.to_s,
      :payload => payload
    @redis.set(key(:worker, id.to_s), data)
  end

  def clear_worker_status(id, redis = @redis)
    redis.del(key(:worker, id.to_s))
  end

  def find_worker(id)
    Worker.attach(self, id)
  end


  #
  # stats
  #

  def info
    return {
      :pending   => stat_pending,
      :processed => stat_processed,
      :queues    => queues.size,
      :workers   => workers.size.to_i,
      :working   => working.size,
      :failed    => stat_failed,
      :servers   => [@redis.server]
    }
  end

  def stat_pending
    queues.inject(0) { |m,k| m + size(k) }
  end

  # Called by workers when a job has been processed,
  # regardless of pass or fail.
  def processed!(id = nil)
    @redis.incr(key(:stats, :processed))
    if id
      @redis.incr(key(:stats, :processed, id.to_s))
    end
  end

  def stat_processed(id = nil)
    target = id ? key(:stats, :processed, id.to_s) : key(:stats, :processed)
    @redis.get(target).to_i
  end

  def clear_processed_for(id, redis = @redis)
    redis.del key(:stats, :processed, id.to_s)
  end

  def failed!(id = nil)
    if id
      @redis.incr(key(:stats, :failed, id.to_s))
    end
  end

  def stat_failed(id = nil)
    id ? @redis.get(key(:stats, :failed, id.to_s)).to_i : failed_size
  end

  def clear_failed_for(id, redis = @redis)
    redis.del key(:stats, :failed, id.to_s)
  end

  def keys
    @redis.keys("resque:*")
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
