require 'resque/core_ext/string'
require 'resque/errors'
require 'resque/job_performer'

module Resque
  # A Resque::Job represents a unit of work. Each job lives on a
  # single queue and has an associated payload object. The payload
  # is a hash with two attributes: `class` and `args`. The `class` is
  # the name of the Ruby class which should be used to run the
  # job. The `args` are an array of arguments which should be passed
  # to the Ruby class's `perform` class-level method.
  #
  # You can manually run a job using this code:
  #
  #   job = Resque::Job.reserve(:high)
  #   klass = job.payload['class'].to_s.constantize
  #   klass.perform(*job.payload['args'])
  class Job
    # @attr [Resque::Worker] worker
    # The worker object which is currently processing this job.
    attr_accessor :worker

    # @attr_reader [#to_s] queue
    # The name of the queue from which this job was pulled (or is to be
    # placed)
    attr_reader :queue

    # @attr_reader [Hash<String,Object>]
    # This job's associated payload object.
    attr_reader :payload

    # @param queue [#to_s]
    # @param payload [Hash<String,Object>]
    # @option payload [#to_s]        'class' - *must* be constantizable into
    #                                          something that responds to perform
    # @option payload [Array<Object>] 'args' - an array of the jobs that will
    #                                          be passed to the job class'
    #                                          perform method.
    def initialize(queue, payload)
      @queue = queue
      @payload = payload
      @failure_hooks_ran = false
    end

    # Creates a job by placing it on a queue. Expects a string queue
    # name, a string class name, and an optional array of arguments to
    # pass to the class' `perform` method.
    #
    # Raises an exception if no queue or class is given.
    # @param queue (see Resque::validate)
    # @param klass (see Resque::validate)
    # @param args [Array<Object>] #coder-serializable array of job arguments
    # @return (see #perform) if Resque::inline?
    # @return [void] unless Resque::inline?
    def self.create(queue, klass, *args)
      coder = Resque.coder
      Resque.validate(klass, queue)

      if Resque.inline?
        # Instantiating a Resque::Job and calling perform on it so callbacks run
        # decode(encode(args)) to ensure that args are normalized in the same
        # manner as a non-inline job
        payload = {'class' => klass, 'args' => coder.decode(coder.encode(args))}

        new(:inline, payload).perform
      else
        Resque.push(queue, 'class' => klass.to_s, 'args' => args)
      end
    end

    # Removes a job from a queue. Expects a string queue name, a
    # string class name, and, optionally, args.
    #
    # Returns the number of jobs destroyed.
    #
    # If no args are provided, it will remove all jobs of the class
    # provided.
    #
    # That is, for these two jobs:
    #
    # { 'class' => 'UpdateGraph', 'args' => ['defunkt'] }
    # { 'class' => 'UpdateGraph', 'args' => ['mojombo'] }
    #
    # The following call will remove both:
    #
    #   Resque::Job.destroy(queue, 'UpdateGraph')
    #
    # Whereas specifying args will only remove the 2nd job:
    #
    #   Resque::Job.destroy(queue, 'UpdateGraph', 'mojombo')
    # @param queue (see #process_queue)
    # @param klass (see #process_queue)
    # @param args (see #process_queue) optional
    # @return [Integer] - the number of jobs destroyed
    def self.destroy(queue, klass, *args)
      coder = Resque.coder
      redis = Resque.backend.store
      klass = klass.to_s

      destroyed_count = 0

      destroyed_count = process_queue(queue, coder, redis, klass, args) do |decoded, new_queue, temp_queue, requeue_queue|
        redis.del(temp_queue).to_i
      end

      destroyed_count.inject(0, :+)
    end

    # Find jobs from a queue. Expects a string queue name, a
    # string class name, and, optionally, args.
    #
    # Returns the list of jobs queued.
    #
    # If no args are provided, it will return all jobs of the class
    # provided.
    #
    # That is, for these two jobs:
    #
    # { 'class' => 'UpdateGraph', 'args' => ['defunkt'] }
    # { 'class' => 'UpdateGraph', 'args' => ['mojombo'] }
    #
    # The following call will find both:
    #
    #   Resque::Job.queued(queue, 'UpdateGraph')
    #
    # Whereas specifying args will only find the 2nd job:
    #
    #   Resque::Job.queued(queue, 'UpdateGraph', 'mojombo')
    # @param queue (see #process_queue)
    # @param klass (see #process_queue)
    # @param args (see #process_queue) optional
    # @return [Array<Resque::Job>]
    def self.queued(queue, klass, *args)
      coder = Resque.coder
      redis = Resque.backend.store
      klass = klass.to_s

      jobs = process_queue(queue, coder, redis, klass, args) do |decoded, new_queue, temp_queue, requeue_queue|
        redis.rpoplpush(temp_queue, requeue_queue)
        new(queue, decoded)
      end

      jobs
    end

    # Given a string queue name, returns an instance of Resque::Job
    # if any jobs are available. If not, returns nil.
    # @param queue (see Resque::pop)
    # @return [Resque::Job]
    def self.reserve(queue)
      if payload = Resque.pop(queue)
        new(queue, payload)
      end
    end

    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    # @return (see JobPerformer#perform)
    def perform
      hooks = {
        :before => before_hooks,
        :around => around_hooks,
        :after => after_hooks
      }
      JobPerformer.new(payload_class, args, hooks).perform
    # If an exception occurs during the job execution, look for an
    # on_failure hook then re-raise.
    rescue Object => e
      run_failure_hooks(e)
      raise e
    end

    # Returns the actual class constant represented in this job's payload.
    # @return [Class]
    # @raise [NameError] if the payload class fails to constantize
    def payload_class
      @payload_class ||= @payload['class'].to_s.constantize
    end

    # Returns the payload class as a string without raising NameError
    # @return [String]
    def payload_class_name
      if has_payload_class?
        payload_class.to_s
      else
        'No Name'
      end
    end

    # @return [Hash<symbol,Object>]
    #   :queue [String] - the queue in which to run
    #   :run_at [String] - iso8601 representation of a UTC timestamp
    #   :payload [Hash<String,Object] (see #payload)
    def to_h
      {
        :queue   => queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => payload
      }
    end

    # returns true if payload_class does not raise NameError
    # @return [Boolean]
    def has_payload_class?
      payload_class != Object
    rescue NameError
      false
    end

    # Returns an array of args represented in this job's payload.
    # @return [Array<Object>]
    def args
      @payload['args']
    end

    # Given an exception object, hands off the needed parameters to
    # the Failure module.
    # @param exception [Exception]
    # @return (see Resque::Failure::create)
    def fail(exception)
      Resque.logger.info "#{inspect} failed: #{exception.inspect}"
      run_failure_hooks(exception) if has_payload_class?
      Failure.create \
        :payload   => payload,
        :exception => exception,
        :worker    => worker,
        :queue     => queue
    rescue Exception => e
      Resque.logger.info "Received exception when reporting failure: #{e.inspect}"
    end

    # Creates an identical job, essentially placing this job back on
    # the queue.
    # @return (see Resque::Job::create)
    def recreate
      self.class.create(queue, payload_class, *args)
    end

    # String representation
    # @return [String]
    def inspect
      obj = @payload
      "(Job{#{@queue}} | #{obj['class']} | #{obj['args'].inspect })"
    end

    # Equality
    # @param other [Resque::Job]
    def ==(other)
      queue == other.queue &&
        payload_class == other.payload_class &&
        args == other.args
    end

    # The before_hooks for the payload_class
    # @return (see Plugin::before_hooks(payload_class))
    def before_hooks
      @before_hooks ||= Plugin.before_hooks(payload_class)
    end

    # The around_hooks for the payload_class
    # @return (see Plugin::around_hooks(payload_class))
    def around_hooks
      @around_hooks ||= Plugin.around_hooks(payload_class)
    end

    # The after_hooks for the payload_class
    # @return (see Plugin::after_hooks(payload_class))
    def after_hooks
      @after_hooks ||= Plugin.after_hooks(payload_class)
    end

    # The failure_hooks for the payload_class
    # @return (see Plugin::failure_hooks(payload_class))
    def failure_hooks
      @failure_hooks ||= Plugin.failure_hooks(payload_class)
    end

    # @param exception [Exception]
    # @return [void]
    def run_failure_hooks(exception)
      job_args = args || []
      unless @failure_hooks_ran
        failure_hooks.each do |hook|
          payload_class.send(hook, exception, *job_args)
        end
      end
    ensure
      @failure_hooks_ran = true
    end

    protected

    # Process a queue, safely moving each item to a temporary queue before
    # processing it. If the job matches, yields to the given block; otherwise,
    # puts it in a requeue_queue, which will eventually be copied back into the
    # source queue.
    # @private
    # @param queue [#to_s]
    # @param coder [Resque::Coder]
    # @param redis [Redis::Namespace,Redis::Distributed]
    # @param klass [String]
    # @param args [Array<Object>]
    # @yieldparam decoded [Hash<String,Object>]
    # @yieldparam new_queue [String] the raw redis key to the queue
    # @yieldparam temp_queue [String] the raw redis key to the temp queue
    # @yieldparam requeue_queue [String] the raw redis key to the requeue queue
    # @yieldreturn [Object] appended to the return array
    # @return [Array<Object>] the results of all matching yields
    def self.process_queue(queue, coder, redis, klass, args)
      return_array  = []
      new_queue     = "queue:#{queue}"
      temp_queue    = "queue:#{queue}:temp:#{Time.now.to_i}"
      requeue_queue = "#{temp_queue}:requeue"

      while string = redis.rpoplpush(new_queue, temp_queue)
        decoded = coder.decode(string)
        if decoded['class'] == klass && (args.empty? || decoded['args'] == args)
          return_array.unshift(yield decoded, new_queue, temp_queue, requeue_queue)
        else
          redis.rpoplpush(temp_queue, requeue_queue)
        end
      end
      push_queue(redis, requeue_queue, new_queue)

      return_array
    end

    # Moves the contents of requeue_queue back onto the queue.
    # @private
    # @param redis [Redis::Namespace,Redis::Distributed]
    # @param requeue_queue [String] the raw redis key to the requeue queue
    # @param queue [String] the raw redis key to the queue
    def self.push_queue(redis, requeue_queue, queue)
      loop { redis.rpoplpush(requeue_queue, queue) or break }
    end
  end
end
