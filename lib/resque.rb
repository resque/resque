require 'mono_logger'
require 'redis/namespace'

require 'resque/version'

require 'resque/errors'

require 'resque/failure/base'
require 'resque/failure'
require 'resque/failure/redis'

require 'resque/globals'
require 'resque/stat'
require 'resque/logging'
require 'resque/job'
require 'resque/worker_registry'
require 'resque/process_coordinator'
require 'resque/worker'
require 'resque/plugin'
require 'resque/queue'
require 'resque/multi_queue'
require 'resque/coder'

require 'forwardable'

module Resque
  extend self

  def self.configure
    yield config
  end

  def redis_id
    config.redis_id
  end

  def namespace=(val)
    config.namespace = val
  end

  def namespace
    config.namespace
  end

  def to_s
    "Resque Backend connected to #{redis_id}"
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

  # Given a queue name, completely deletes the queue.
  def remove_queue(queue)
    queue(queue).destroy
    @queues.delete(queue.to_s)
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
    if klass.instance_variable_defined?(:@queue)
      klass.instance_variable_get(:@queue)
    else
      (klass.respond_to?(:queue) and klass.queue)
    end
  end

  #
  # stats
  #

  # Returns a hash, similar to redis-rb's #info, of interesting stats.
  def info
    {
      :pending   => pending_queues,
      :processed => Stat[:processed],
      :queues    => queues.size,
      :workers   => Resque::WorkerRegistry.all.size.to_i,
      :working   => Resque::WorkerRegistry.working.size,
      :failed    => failed_job_count,
      :servers   => [redis_id],
      :environment  => environment
    }
  end

  def pending_queues
    queues.inject(0) { |m,k| m + size(k) }
  end

  def failed_job_count
    Resque.backend.store.llen(:failed).to_i
  end

  def environment
    ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
  end

  # Returns an array of all known Resque keys in Redis. Redis' KEYS operation
  # is O(N) for the keyspace, so be careful - this can be slow for big databases.
  def keys
    backend.store.keys("*").map do |key|
      key.sub("#{backend.store.namespace}:", '')
    end
  end
end

# Log to STDOUT by default
Resque.logger = MonoLogger.new(STDOUT)
