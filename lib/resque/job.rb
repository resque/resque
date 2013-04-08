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
  #   klass = Resque::Job.constantize(job.payload['class'])
  #   klass.perform(*job.payload['args'])
  class Job
    def redis
      Resque.redis
    end

    def self.redis
      Resque.redis
    end

    def self.encode(object)
      Resque.coder.encode(object)
    end

    def self.decode(object)
      Resque.coder.decode(object)
    end

    def encode(object)
      Resque.coder.encode(object)
    end

    def decode(object)
      Resque.coder.decode(object)
    end

    def constantize(camel_cased_word)
      names = camel_cased_word.to_s.split('::')
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        if constant == Object
          constant.const_get(name)
        else
          candidate = constant.const_get(name)
          args = Module.method(:const_defined?).arity != 1 ? [false] : []
          next candidate if constant.const_defined?(name, *args)
          next candidate unless Object.const_defined?(name)

          # Go down the ancestors to check it it's owned
          # directly before we reach Object or the end of ancestors.
          constant = constant.ancestors.inject do |const, ancestor|
            break const    if ancestor == Object
            break ancestor if ancestor.const_defined?(name, *args)
            const
          end

          # owner is in Object, so raise
          constant.const_get(name, false)
        end
      end
    end

    # Raise Resque::Job::DontPerform from a before_perform hook to
    # abort the job.
    DontPerform = Class.new(StandardError)

    # The worker object which is currently processing this job.
    attr_accessor :worker

    # The name of the queue from which this job was pulled (or is to be
    # placed)
    attr_reader :queue

    # This job's associated payload object.
    attr_reader :payload

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
    def self.create(queue, klass, *args)
      Resque.validate(klass, queue)

      if Resque.inline?
        # Instantiating a Resque::Job and calling perform on it so callbacks run
        # decode(encode(args)) to ensure that args are normalized in the same
        # manner as a non-inline job
        payload = {'class' => klass, 'args' => decode(encode(args))}

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
    def self.destroy(queue, klass, *args)
      klass = klass.to_s
      args  = decode(encode(args))
      queue = "queue:#{queue}"
      destroyed = 0

      tmp_queue = "#{queue}:tmp:#{Time.now.to_i}"
      requeue_queue = "#{tmp_queue}:requeue"
      while string = redis.rpoplpush(queue, tmp_queue)
        decoded = decode(string)
        if decoded['class'] == klass && (args.empty? || decoded['args'] == args)
          destroyed += redis.del(tmp_queue).to_i
        else
          redis.rpoplpush(tmp_queue, requeue_queue)
        end
      end
      loop do
        redis.rpoplpush(requeue_queue, queue) or break
      end

      destroyed
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
    def self.queued(queue, klass, *args)
      klass = klass.to_s
      tmp_queue = "queue:#{queue}:tmp:#{Time.now.to_i}"
      requeue_queue = "#{tmp_queue}:requeue"
      jobs = []

      while string = redis.rpoplpush("queue:#{queue}", tmp_queue)
        decoded = decode(string)
        if decoded['class'] == klass && (args.empty? || decoded['args'] == args)
          jobs.unshift new(queue, decoded)
        end
        redis.rpoplpush(tmp_queue, requeue_queue)
      end
      loop do
        redis.rpoplpush(requeue_queue, "queue:#{queue}") or break
      end

      jobs
    end

    # Given a string queue name, returns an instance of Resque::Job
    # if any jobs are available. If not, returns nil.
    def self.reserve(queue)
      if payload = Resque.pop(queue)
        new(queue, payload)
      end
    end

    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    def perform
      begin
        hooks = {
          :before => before_hooks,
          :around => around_hooks,
          :after => after_hooks
        }
        JobPerformer.new.perform(payload_class, args, hooks)
      # If an exception occurs during the job execution, look for an
      # on_failure hook then re-raise.
      rescue Object => e
        run_failure_hooks(e)
        raise e
      end
    end

    # Returns the actual class constant represented in this job's payload.
    def payload_class
      @payload_class ||= constantize(@payload['class'])
    end

    # Returns the payload class as a string without raising NameError
    def payload_class_name
      if has_payload_class?
        payload_class.to_s
      else
        'No Name'
      end
    end


    def to_h
      {
        :queue   => queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => payload
      }
    end

    # returns true if payload_class does not raise NameError
    def has_payload_class?
      payload_class != Object
    rescue NameError
      false
    end

    # Returns an array of args represented in this job's payload.
    def args
      @payload['args']
    end

    # Given an exception object, hands off the needed parameters to
    # the Failure module.
    def fail(exception)
      Resque.logger.info "#{inspect} failed: #{exception.inspect}"
      begin
        run_failure_hooks(exception) if has_payload_class?
        Failure.create \
          :payload   => payload,
          :exception => exception,
          :worker    => worker,
          :queue     => queue
      rescue Exception => e
        Resque.logger.info "Received exception when reporting failure: #{e.inspect}"
      end
    end

    # Creates an identical job, essentially placing this job back on
    # the queue.
    def recreate
      self.class.create(queue, payload_class, *args)
    end

    # String representation
    def inspect
      obj = @payload
      "(Job{#{@queue}} | #{obj['class']} | #{obj['args'].inspect })"
    end

    # Equality
    def ==(other)
      queue == other.queue &&
        payload_class == other.payload_class &&
        args == other.args
    end

    def before_hooks
      @before_hooks ||= Plugin.before_hooks(payload_class)
    end

    def around_hooks
      @around_hooks ||= Plugin.around_hooks(payload_class)
    end

    def after_hooks
      @after_hooks ||= Plugin.after_hooks(payload_class)
    end

    def failure_hooks
      @failure_hooks ||= Plugin.failure_hooks(payload_class)
    end

    def run_failure_hooks(exception)
      begin
        job_args = args || []
        unless @failure_hooks_ran
          failure_hooks.each do |hook|
            payload_class.send(hook, exception, *job_args)
          end
        end
      ensure
        @failure_hooks_ran = true
      end
    end
  end
end
