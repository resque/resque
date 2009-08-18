require 'redis'
require 'yajl'

require 'resque/job'
require 'resque/worker'

class Resque
  attr_reader :redis

  #
  # We need a Redis server to connect to
  #

  def self.redis=(server)
    case server
    when String
      host, port = server.split(':')
      @redis = Redis.new(:host => host, :port => port)
    when Redis
      @redis = server
    else
      raise "I don't know what to do with #{servers.inspect}"
    end
  end

  def self.redis
    @redis ||= Redis.new(:host => 'localhost', :port => 6379)
  end

  def initialize(server = nil)
    Resque.redis = server if server
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
    redis_push [ :queue, queue ], item
  end

  def pop(queue)
    redis_shift [ :queue, queue ]
  end

  def size(queue)
    redis_list_length [ :queue, queue ]
  end

  def peek(queue, start = 0, count = 1)
    redis_list_range [ :queue, queue ], start, count
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
    @redis.rpush key(list), encode(value)
  end

  def redis_shift(list)
    decode @redis.lpop(key(list))
  end

  def redis_list_length(list)
    @redis.llen(key(list)).to_i
  end

  def redis_list_range(list, start = 0, count = 1)
    if count == 1
      decode @redis.lindex(key(list), start)
    else
      Array(@redis.lrange(key(list), start, start+count-1)).map do |item|
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

  def set_worker_status(id, job)
    data = encode \
      :queue   => job.queue,
      :run_at  => Time.now.to_s,
      :payload => job.payload
    @redis.set(key(:worker, id.to_s), data)
  end

  def clear_worker_status(id, redis = @redis)
    redis.del(key(:worker, id.to_s))
  end

  def find_worker(id)
    Worker.attach(id)
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
  def processed!(worker = nil)
    @redis.incr(key(:stats, :processed))
    @redis.incr(key(:stats, :processed, worker.to_s)) if worker
  end

  def stat_processed(id = nil)
    target = id ? key(:stats, :processed, id.to_s) : key(:stats, :processed)
    @redis.get(target).to_i
  end

  def clear_processed_for(id, redis = @redis)
    redis.del key(:stats, :processed, id.to_s)
  end

  def failed!(worker)
    @redis.incr(key(:stats, :failed, worker.to_s))
  end

  def stat_failed(id = nil)
    id ? @redis.get(key(:stats, :failed, id.to_s)).to_i : Job.failed_size
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
