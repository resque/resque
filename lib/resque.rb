require 'mono_logger'
require 'redis/namespace'
require 'forwardable'

require 'resque/version'

require 'resque/errors'

require 'resque/failure'
require 'resque/failure/base'

require 'resque/helpers'
require 'resque/stat'
require 'resque/logging'
require 'resque/log_formatters/quiet_formatter'
require 'resque/log_formatters/verbose_formatter'
require 'resque/log_formatters/very_verbose_formatter'
require 'resque/job'
require 'resque/worker'
require 'resque/plugin'
require 'resque/data_store'
require 'resque/thread_signal'

require 'resque/vendor/utf8_util'

require 'resque/railtie' if defined?(Rails::Railtie)

module Resque
  include Helpers
  extend self

  # Given a Ruby object, returns a string suitable for storage in a
  # queue.
  def encode(object)
    if MultiJson.respond_to?(:dump) && MultiJson.respond_to?(:load)
      MultiJson.dump object
    else
      MultiJson.encode object
    end
  end

  # Given a string, returns a Ruby object.
  def decode(object)
    return unless object

    begin
      if MultiJson.respond_to?(:dump) && MultiJson.respond_to?(:load)
        MultiJson.load object
      else
        MultiJson.decode object
      end
    rescue ::MultiJson::DecodeError => e
      raise Helpers::DecodeException, e.message, e.backtrace
    end
  end

  # Given a word with dashes, returns a camel cased version of it.
  #
  # classify('job-name') # => 'JobName'
  def classify(dashed_word)
    dashed_word.split('-').map(&:capitalize).join
  end

  # Tries to find a constant with the name specified in the argument string:
  #
  # constantize("Module") # => Module
  # constantize("Test::Unit") # => Test::Unit
  #
  # The name is assumed to be the one of a top-level constant, no matter
  # whether it starts with "::" or not. No lexical context is taken into
  # account:
  #
  # C = 'outside'
  # module M
  #   C = 'inside'
  #   C # => 'inside'
  #   constantize("C") # => 'outside', same as ::C
  # end
  #
  # NameError is raised when the constant is unknown.
  def constantize(camel_cased_word)
    camel_cased_word = camel_cased_word.to_s

    if camel_cased_word.include?('-')
      camel_cased_word = classify(camel_cased_word)
    end

    names = camel_cased_word.split('::')
    names.shift if names.empty? || names.first.empty?

    constant = Object
    names.each do |name|
      args = Module.method(:const_get).arity != 1 ? [false] : []

      if constant.const_defined?(name, *args)
        constant = constant.const_get(name)
      else
        constant = constant.const_missing(name)
      end
    end
    constant
  end

  extend ::Forwardable

  # Accepts:
  #   1. A 'hostname:port' String
  #   2. A 'hostname:port:db' String (to select the Redis db)
  #   3. A 'hostname:port/namespace' String (to set the Redis namespace)
  #   4. A Redis URL String 'redis://host:port'
  #   5. An instance of `Redis`, `Redis::Client`, `Redis::DistRedis`,
  #      or `Redis::Namespace`.
  #   6. An Hash of a redis connection {:host => 'localhost', :port => 6379, :db => 0}
  def redis=(server)
    case server
    when String
      if server =~ /rediss?\:\/\//
        redis = Redis.new(:url => server)
      else
        server, namespace = server.split('/', 2)
        host, port, db = server.split(':')
        redis = Redis.new(:host => host, :port => port, :db => db)
      end
      namespace ||= :resque

      @data_store = Resque::DataStore.new(Redis::Namespace.new(namespace, :redis => redis))
    when Redis::Namespace
      @data_store = Resque::DataStore.new(server)
    when Resque::DataStore
      @data_store = server
    when Hash
      @data_store = Resque::DataStore.new(Redis::Namespace.new(:resque, :redis => Redis.new(server)))
    else
      @data_store = Resque::DataStore.new(Redis::Namespace.new(:resque, :redis => server))
    end
  end

  # Returns the current Redis connection. If none has been created, will
  # create a new one.
  def redis
    return @data_store if @data_store
    self.redis = Redis.respond_to?(:connect) ? Redis.connect : "localhost:6379"
    self.redis
  end
  alias :data_store :redis

  def redis_id
    data_store.identifier
  end

  # Set the data store for the processed and failed statistics.
  #
  # By default it uses the same as `Resque.redis`, but different stores can be used.
  #
  # A custom store needs to obey the following API to work correctly
  #
  # class NullDataStore
  #   # Returns the current value for the given stat.
  #   def stat(stat)
  #   end
  #
  #   # Increments the stat by the given value.
  #   def increment_stat(stat, by)
  #   end
  #
  #   # Decrements the stat by the given value.
  #   def decrement_stat(stat, by)
  #   end
  #
  #   # Clear the values for the given stat.
  #   def clear_stat(stat)
  #   end
  # end
  def stat_data_store=(stat_data_store)
    Resque::Stat.data_store = stat_data_store
  end

  # Returns the data store for the statistics module.
  def stat_data_store
    Resque::Stat.data_store
  end

  # Set or retrieve the current logger object
  attr_accessor :logger

  DEFAULT_HEARTBEAT_INTERVAL = 60
  DEFAULT_PRUNE_INTERVAL = DEFAULT_HEARTBEAT_INTERVAL * 5

  # Defines how often a Resque worker updates the heartbeat key. Must be less
  # than the prune interval.
  attr_writer :heartbeat_interval
  def heartbeat_interval
    if defined? @heartbeat_interval
      @heartbeat_interval
    else
      DEFAULT_HEARTBEAT_INTERVAL
    end
  end

  # Defines how often Resque checks for dead workers.
  attr_writer :prune_interval
  def prune_interval
    if defined? @prune_interval
      @prune_interval
    else
      DEFAULT_PRUNE_INTERVAL
    end
  end

  # By default, jobs are pushed to the back of the queue and popped from
  # the front, resulting in "first in, first out" (FIFO) execution order.
  # Set to true to push jobs to the front of the queue instead, resulting
  # in "last in, first out" (LIFO) execution order.
  attr_writer :enqueue_front
  def enqueue_front
    if defined? @enqueue_front
      @enqueue_front
    else
      @enqueue_front = false
    end
  end

  # The `before_first_fork` hook will be run in the **parent** process
  # only once, before forking to run the first job. Be careful- any
  # changes you make will be permanent for the lifespan of the
  # worker.
  #
  # Call with a block to register a hook.
  # Call with no arguments to return all registered hooks.
  def before_first_fork(&block)
    block ? register_hook(:before_first_fork, block) : hooks(:before_first_fork)
  end

  # Register a before_first_fork proc.
  def before_first_fork=(block)
    register_hook(:before_first_fork, block)
  end

  # The `before_fork` hook will be run in the **parent** process
  # before every job, so be careful- any changes you make will be
  # permanent for the lifespan of the worker.
  #
  # Call with a block to register a hook.
  # Call with no arguments to return all registered hooks.
  def before_fork(&block)
    block ? register_hook(:before_fork, block) : hooks(:before_fork)
  end

  # Register a before_fork proc.
  def before_fork=(block)
    register_hook(:before_fork, block)
  end

  # The `after_fork` hook will be run in the child process and is passed
  # the current job. Any changes you make, therefore, will only live as
  # long as the job currently being processed.
  #
  # Call with a block to register a hook.
  # Call with no arguments to return all registered hooks.
  def after_fork(&block)
    block ? register_hook(:after_fork, block) : hooks(:after_fork)
  end

  # Register an after_fork proc.
  def after_fork=(block)
    register_hook(:after_fork, block)
  end

  # The `before_pause` hook will be run in the parent process before the
  # worker has paused processing (via #pause_processing or SIGUSR2).
  def before_pause(&block)
    block ? register_hook(:before_pause, block) : hooks(:before_pause)
  end

  # Register a before_pause proc.
  def before_pause=(block)
    register_hook(:before_pause, block)
  end

  # The `after_pause` hook will be run in the parent process after the
  # worker has paused (via SIGCONT).
  def after_pause(&block)
    block ? register_hook(:after_pause, block) : hooks(:after_pause)
  end

  # Register an after_pause proc.
  def after_pause=(block)
    register_hook(:after_pause, block)
  end

  # The `queue_empty` hook will be run in the **parent** process when
  # the worker finds no more jobs in the queue and becomes idle.
  #
  # Call with a block to register a hook.
  # Call with no arguments to return all registered hooks.
  def queue_empty(&block)
    block ? register_hook(:queue_empty, block) : hooks(:queue_empty)
  end

  # Register a queue_empty proc.
  def queue_empty=(block)
    register_hook(:queue_empty, block)
  end

  # The `worker_exit` hook will be run in the **parent** process
  # after the worker has existed (via SIGQUIT, SIGTERM, SIGINT, etc.).
  #
  # Call with a block to register a hook.
  # Call with no arguments to return all registered hooks.
  def worker_exit(&block)
    block ? register_hook(:worker_exit, block) : hooks(:worker_exit)
  end

  # Register a worker_exit proc.
  def worker_exit=(block)
    register_hook(:worker_exit, block)
  end

  def to_s
    "Resque Client connected to #{redis_id}"
  end

  attr_accessor :inline

  # If 'inline' is true Resque will call #perform method inline
  # without queuing it into Redis and without any Resque callbacks.
  # The 'inline' is false Resque jobs will be put in queue regularly.
  alias :inline? :inline

  #
  # queue manipulation
  #

  # Pushes a job onto a queue. Queue name should be a string and the
  # item should be any JSON-able Ruby object.
  #
  # Resque works generally expect the `item` to be a hash with the following
  # keys:
  #
  #   class - The String name of the job to run.
  #    args - An Array of arguments to pass the job. Usually passed
  #           via `class.to_class.perform(*args)`.
  #
  # Example
  #
  #   Resque.push('archive', :class => 'Archive', :args => [ 35, 'tar' ])
  #
  # Returns nothing
  def push(queue, item)
    data_store.push_to_queue(queue,encode(item))
  end

  # Pops a job off a queue. Queue name should be a string.
  #
  # Returns a Ruby object.
  def pop(queue)
    decode(data_store.pop_from_queue(queue))
  end

  # Returns an integer representing the size of a queue.
  # Queue name should be a string.
  def size(queue)
    data_store.queue_size(queue)
  end

  # Returns an array of items currently queued, or the item itself
  # if count = 1. Queue name should be a string.
  #
  # start and count should be integer and can be used for pagination.
  # start is the item to begin, count is how many items to return.
  #
  # To get the 3rd page of a 30 item, paginatied list one would use:
  #   Resque.peek('my_list', 59, 30)
  def peek(queue, start = 0, count = 1)
    results = data_store.peek_in_queue(queue,start,count)
    if count == 1
      decode(results)
    else
      results.map { |result| decode(result) }
    end
  end

  # Does the dirty work of fetching a range of items from a Redis list
  # and converting them into Ruby objects.
  def list_range(key, start = 0, count = 1)
    results = data_store.list_range(key, start, count)
    if count == 1
      decode(results)
    else
      results.map { |result| decode(result) }
    end
  end

  # Returns an array of all known Resque queues as strings.
  def queues
    data_store.queue_names
  end

  # Given a queue name, completely deletes the queue.
  def remove_queue(queue)
    data_store.remove_queue(queue)
  end

  # Used internally to keep track of which queues we've created.
  # Don't call this directly.
  def watch_queue(queue)
    data_store.watch_queue(queue)
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

  # Given a class, try to extrapolate an appropriate queue based on a
  # class instance variable or `queue` method.
  def queue_from_class(klass)
    (klass.instance_variable_defined?(:@queue) && klass.instance_variable_get(:@queue)) ||
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

    if !queue
      raise NoQueueError.new("Jobs must be placed onto a queue. No queue could be inferred for class #{klass}")
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
    return {
      :pending   => queue_sizes.inject(0) { |sum, (_queue_name, queue_size)| sum + queue_size },
      :processed => Stat[:processed],
      :queues    => queues.size,
      :workers   => workers.size.to_i,
      :working   => working.size,
      :failed    => data_store.num_failed,
      :servers   => [redis_id],
      :environment  => ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    }
  end

  # Returns an array of all known Resque keys in Redis. Redis' KEYS operation
  # is O(N) for the keyspace, so be careful - this can be slow for big databases.
  def keys
    data_store.all_resque_keys
  end

  # Returns a hash, mapping queue names to queue sizes
  def queue_sizes
    queue_names = queues

    sizes = redis.pipelined do |piped|
      queue_names.each do |name|
        piped.llen("queue:#{name}")
      end
    end

    Hash[queue_names.zip(sizes)]
  end

  # Returns a hash, mapping queue names to (up to `sample_size`) samples of jobs in that queue
  def sample_queues(sample_size = 1000)
    queue_names = queues

    samples = redis.pipelined do |piped|
      queue_names.each do |name|
        key = "queue:#{name}"
        piped.llen(key)
        piped.lrange(key, 0, sample_size - 1)
      end
    end

    hash = {}

    queue_names.zip(samples.each_slice(2).to_a) do |queue_name, (queue_size, serialized_samples)|
      samples = serialized_samples.map do |serialized_sample|
        Job.decode(serialized_sample)
      end

      hash[queue_name] = {
        :size => queue_size,
        :samples => samples
      }
    end

    hash
  end

  private

  @hooks = Hash.new { |h, k| h[k] = [] }

  # Register a new proc as a hook. If the block is nil this is the
  # equivalent of removing all hooks of the given name.
  #
  # `name` is the hook that the block should be registered with.
  def register_hook(name, block)
    return clear_hooks(name) if block.nil?

    block = Array(block)
    @hooks[name].concat(block)
  end

  # Clear all hooks given a hook name.
  def clear_hooks(name)
    @hooks[name] = []
  end

  # Retrieve all hooks of a given name.
  def hooks(name)
    @hooks[name]
  end
end

# Log to STDOUT by default
Resque.logger           = MonoLogger.new(STDOUT)
Resque.logger.formatter = Resque::QuietFormatter.new
