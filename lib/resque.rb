require 'mono_logger'
require 'redis/namespace'

require "core_ext/hash"

require 'resque/version'
require 'resque/config'

require 'resque/errors'

require 'resque/failure/base'
require 'resque/failure'
require 'resque/failure/redis'

require 'resque/helpers'
require 'resque/stat'
require 'resque/logging'
require 'resque/job'
require 'resque/worker'
require 'resque/plugin'
require 'resque/queue'
require 'resque/multi_queue'
require 'resque/coder'
require 'resque/json_coder'
require 'resque/redis_factory'
require 'resque/hook_register'

require 'resque/vendor/utf8_util'

module Resque
  include Helpers
  extend self

  extend Forwardable

  def self.config=(options = {})
    @config = Config.new(options)
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield config
  end

  # Accepts:
  #   1. A 'hostname:port' String
  #   2. A 'hostname:port:db' String (to select the Redis db)
  #   3. A 'hostname:port/namespace' String (to set the Redis namespace)
  #   4. A Redis URL String 'redis://host:port'
  #   5. An instance of `Redis`, `Redis::Client`, `Redis::DistRedis`,
  #      or `Redis::Namespace`.
  def redis=(server)
    @redis = RedisFactory.from_server(server)

    @queues = Hash.new do |h,name|
      h[name] = Resque::Queue.new(name, @redis, coder)
    end
  end

  # Encapsulation of encode/decode. Overwrite this to use it across Resque.
  # This defaults to JSON for backwards compatibility.
  def coder
    @coder ||= JsonCoder.new
  end
  attr_writer :coder

  # Returns the current Redis connection. If none has been created, will
  # create a new one.
  def redis
    return @redis if @redis

    self.redis = if Redis.respond_to?(:connect) 
      Redis.connect(:thread_safe => true)
    else
      "localhost:6379"
    end
  end

  def redis_id
    # support 1.x versions of redis-rb
    if redis.respond_to?(:server)
      redis.server
    elsif redis.respond_to?(:nodes) # distributed
      redis.nodes.map { |n| n.id }.join(', ')
    else
      redis.client.id
    end
  end

  # Set or retrieve the current logger object
  attr_accessor :logger

  @hook_register = HookRegister.new

  def_delegators :@hook_register,
    :before_first_fork,
    :before_first_fork=,
    :before_fork,
    :before_fork=,
    :after_fork,
    :after_fork=,
    :before_pause,
    :before_pause=,
    :after_pause,
    :after_pause=,
    :before_perform,
    :before_perform=,
    :after_perform,
    :after_perform=

  def to_s
    "Resque Client connected to #{redis_id}"
  end

  # If 'inline' is true Resque will call #perform method inline
  # without queuing it into Redis and without any Resque callbacks.
  # The 'inline' is false Resque jobs will be put in queue regularly.
  attr_writer :inline

  def inline(&block)
    block ? inline_block(&block) : inline?
  end

  def inline_block
    self.inline = true
    yield
  ensure
    self.inline = false
  end

  def inline?
    @inline
  end

  #
  # queue manipulation
  #

  # Pushes a job onto a queue. Queue name should be a string and the
  # item should be any JSON-able Ruby object.
  #
  # Resque workers generally expect the `item` to be a hash with the following
  # keys:
  #
  #   class - The String name of the job to run.
  #    args - An Array of arguments to pass the job. Usually passed
  #           via `class.to_class.perform(*args)`.
  #
  # Example
  #
  #   Resque.push('archive', 'class' => 'Archive', 'args' => [ 35, 'tar' ])
  #
  # Returns nothing
  def push(queue, item)
    queue(queue) << item
  end

  # Pops a job off a queue. Queue name should be a string.
  #
  # Returns a Ruby object.
  def pop(queue)
    begin
      queue(queue).pop(true)
    rescue ThreadError
      nil
    end
  end

  # Returns an integer representing the size of a queue.
  # Queue name should be a string.
  def size(queue)
    queue(queue).size
  end

  # Returns an array of items currently queued. Queue name should be
  # a string.
  #
  # start and count should be integer and can be used for pagination.
  # start is the item to begin, count is how many items to return.
  #
  # To get the 3rd page of a 30 items, paginated list one would use:
  #   Resque.peek('my_list', 59, 30)
  def peek(queue, start = 0, count = 1)
    result = queue(queue).slice(start, count)

    if result.nil?
      []
    elsif result.respond_to?(:to_ary)
      result.to_ary || [result]
    else
      [result]
    end
  end

  # Does the dirty work of fetching a range of items from a Redis list
  # and converting them into Ruby objects.
  def list_range(key, start = 0, count = 1)
    if count == 1
      decode(redis.lindex(key, start))
    else
      Array(redis.lrange(key, start, start+count-1)).map do |item|
        decode(item)
      end
    end
  end

  # Returns an array of all known Resque queues as strings.
  def queues
    Array(redis.smembers(:queues))
  end

  # Given a queue name, completely deletes the queue.
  def remove_queue(queue)
    queue(queue).destroy
    @queues.delete(queue.to_s)
  end

  # Return the Resque::Queue object for a given name
  def queue(name)
    @queues[name.to_s]
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
  # If no queue can be inferred this method will raise a `Resque::NoQueueError`
  #
  # Returns true if the job was queued, nil if the job was rejected by a
  # before_enqueue hook.
  #
  # This method is considered part of the `stable` API.
  def enqueue(klass, *args)
    enqueue_to(queue_from_class(klass), klass, *args)
  end

  # Just like `enqueue` but allows you to specify the queue you want to
  # use. Runs hooks.
  #
  # `queue` should be the String name of the queue you're targeting.
  #
  # Returns true if the job was queued, nil if the job was rejected by a
  # before_enqueue hook.
  #
  # This method is considered part of the `stable` API.
  def enqueue_to(queue, klass, *args)
    validate(klass, queue)
    # Perform before_enqueue hooks. Don't perform enqueue if any hook returns false
    before_hooks = Plugin.before_enqueue_hooks(klass).collect do |hook|
      klass.send(hook, *args)
    end
    return nil if before_hooks.any? { |result| result == false }

    Job.create(queue, klass, *args)

    Plugin.after_enqueue_hooks(klass).each do |hook|
      klass.send(hook, *args)
    end

    return true
  end

  # This method can be used to conveniently remove a job from a queue.
  # It assumes the class you're passing it is a real Ruby class (not
  # a string or reference) which either:
  #
  #   a) has a @queue ivar set
  #   b) responds to `queue`
  #
  # If either of those conditions are met, it will use the value obtained
  # from performing one of the above operations to determine the queue.
  #
  # If no queue can be inferred this method will raise a `Resque::NoQueueError`
  #
  # If no args are given, this method will dequeue *all* jobs matching
  # the provided class. See `Resque::Job.destroy` for more
  # information.
  #
  # Returns the number of jobs destroyed.
  #
  # Example:
  #
  #   # Removes all jobs of class `UpdateNetworkGraph`
  #   Resque.dequeue(GitHub::Jobs::UpdateNetworkGraph)
  #
  #   # Removes all jobs of class `UpdateNetworkGraph` with matching args.
  #   Resque.dequeue(GitHub::Jobs::UpdateNetworkGraph, 'repo:135325')
  #
  # This method is considered part of the `stable` API.
  def dequeue(klass, *args)
    # Perform before_dequeue hooks. Don't perform dequeue if any hook returns false
    before_hooks = Plugin.before_dequeue_hooks(klass).collect do |hook|
      klass.send(hook, *args)
    end
    return if before_hooks.any? { |result| result == false }

    destroyed = Job.destroy(queue_from_class(klass), klass, *args)

    Plugin.after_dequeue_hooks(klass).each do |hook|
      klass.send(hook, *args)
    end
    
    destroyed
  end

  # This method will return an array of `Resque::Job` object in a queue.
  # It assumes the class you're passing it is a real Ruby class (not
  # a string or reference) which either:
  #
  #   a) has a @queue ivar set
  #   b) responds to `queue`
  #
  # If either of those conditions are met, it will use the value obtained
  # from performing one of the above operations to determine the queue.
  #
  # If no queue can be inferred this method will raise a `Resque::NoQueueError`

  def queued(klass, *args)
    Job.queued(queue_from_class(klass), klass, *args)
  end

  # Given a class, try to extrapolate an appropriate queue based on a
  # class instance variable or `queue` method.
  def queue_from_class(klass)
    klass.instance_variable_get(:@queue) ||
      (klass.respond_to?(:queue) and klass.queue)
  end

  # This method will return a `Resque::Job` object or a non-true value
  # depending on whether a job can be obtained. You should pass it the
  # precise name of a queue: case matters.
  #
  # This method is considered part of the `stable` API.
  def reserve(queue)
    Job.reserve(queue)
  end

  # Validates if the given klass could be a valid Resque job
  #
  # If no queue can be inferred this method will raise a `Resque::NoQueueError`
  #
  # If given klass is nil this method will raise a `Resque::NoClassError`
  def validate(klass, queue = nil)
    queue ||= queue_from_class(klass)

    unless queue
      raise NoQueueError.new("Jobs must be placed onto a queue.")
    end

    if klass.to_s.empty?
      raise NoClassError.new("Jobs must be given a class.")
    end
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

  # A shortcut to unregister_worker
  # useful for command line tool
  def remove_worker(worker_id)
    worker = Resque::Worker.find(worker_id)
    worker.unregister_worker
  end

  #
  # stats
  #

  # Returns a hash, similar to redis-rb's #info, of interesting stats.
  def info
    {
      :pending   => queues.inject(0) { |m,k| m + size(k) },
      :processed => Stat[:processed],
      :queues    => queues.size,
      :workers   => workers.size.to_i,
      :working   => working.size,
      :failed    => Resque.redis.llen(:failed).to_i,
      :servers   => [redis_id],
      :environment  => ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    }
  end

  # Returns an array of all known Resque keys in Redis. Redis' KEYS operation
  # is O(N) for the keyspace, so be careful - this can be slow for big databases.
  def keys
    redis.keys("*").map do |key|
      key.sub("#{redis.namespace}:", '')
    end
  end
end

# Log to STDOUT by default
Resque.logger           = MonoLogger.new(STDOUT)
