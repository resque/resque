require 'resque/json_coder'
require 'resque/backend'
require 'resque/config'
require 'resque/hook_register'

module Resque

  class << self

    def encode(object)
      Resque.coder.encode(object)
    end

    def decode(object)
      Resque.coder.decode(object)
    end

    extend Forwardable

    def config=(options = {})
      @config = Config.new(options)
    end

    def config
      @config ||= Config.new
    end

    def backend
      @backend ||= Backend.new(config.redis, Resque.logger)
    end

    def redis=(server)
      config.redis = server

      @queues = Hash.new do |h,name|
        h[name] = Resque::Queue.new(name, config.redis, coder)
      end

      @backend = Backend.new(config.redis, Resque.logger)

      config.redis
    end

    # Encapsulation of encode/decode. Overwrite this to use it across Resque.
    # This defaults to JSON for backwards compatibility.
    def coder
      @coder ||= JsonCoder.new
    end
    attr_writer :coder

    # Set or retrieve the current logger object
    attr_accessor :logger

    def hook_register
      @hook_register ||= HookRegister.new
    end

    def_delegators :hook_register,
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
      @inline if defined?(@inline)
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
      queue(queue).pop(true)
    rescue ThreadError
      nil
    end

    # Does the dirty work of fetching a range of items from a Redis list
    # and converting them into Ruby objects.
    def list_range(key, start = 0, count = 1)
      if count == 1
        decode(backend.store.lindex(key, start))
      else
        Array(backend.store.lrange(key, start, start+count-1)).map do |item|
          decode(item)
        end
      end
    end

    # Returns an array of all known Resque queues as strings.
    def queues
      Array(backend.store.smembers(:queues))
    end

    # Return the Resque::Queue object for a given name
    def queue(name)
      @queues[name.to_s]
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

  end

end