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
    include Helpers
    extend Helpers

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
    end

    # Creates a job by placing it on a queue. Expects a string queue
    # name, a string class name, and an optional array of arguments to
    # pass to the class' `perform` method.
    #
    # Raises an exception if no queue or class is given.
    def self.create(queue, klass, *args)
      if !queue
        raise NoQueueError.new("Jobs must be placed onto a queue.")
      end

      if klass.to_s.empty?
        raise NoClassError.new("Jobs must be given a class.")
      end

      Resque.push(queue, :class => klass.to_s, :args => args)
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
    #
    # This method can be potentially very slow and memory intensive,
    # depending on the size of your queue, as it loads all jobs into
    # a Ruby array before processing.
    def self.destroy(queue, klass, *args)
      klass = klass.to_s
      queue = "queue:#{queue}"
      destroyed = 0

      redis.lrange(queue, 0, -1).each do |string|
        json   = decode(string)

        match  = json['class'] == klass
        match &= json['args'] == args unless args.empty?

        if match
          destroyed += redis.lrem(queue, 0, string).to_i
        end
      end

      destroyed
    end

    # Given a string queue name, returns an instance of Resque::Job
    # if any jobs are available. If not, returns nil.
    def self.reserve(queue)
      return unless payload = Resque.pop(queue)
      new(queue, payload)
    end

    # Attempts to perform the work represented by this job instance.
    # Calls #perform on the class given in the payload with the
    # arguments given in the payload.
    def perform
      job_args = args || []
      job_was_performed = false

      # Plugins may come via modules extended which implement Resque::Plugin.
      # We also treat the payload_class itself like the last plugin.
      plugins = payload_class.instance_variable_get(:@plugins) || []
      plugins << payload_class

      begin
        # Execute before_perform hook. Abort the job gracefully if
        # Resque::DontPerform is raised.
        begin
          plugins.each { |p| p.before_perform(*job_args) if p.respond_to?(:before_perform) }
        rescue DontPerform
          return false
        end

        # Execute the job. Do it in an around_perform hook if available.
        around_plugins = plugins.select { |p| p.respond_to?(:around_perform) }.reverse

        if around_plugins.empty?
          payload_class.perform(*job_args)
          job_was_performed = true
        else
          # We want to nest all around_perform plugins, with the last one
          # finally calling perform
          stack = around_plugins.inject(nil) do |last_plugin, plugin|
            if last_plugin
              lambda do
                plugin.around_perform(*job_args) { last_plugin.call }
              end
            else
              lambda do
                plugin.around_perform(*job_args) do
                  payload_class.perform(*job_args)
                  job_was_performed = true
                end
              end
            end
          end
          stack.call
        end

        # Execute after_perform hook
        plugins.each { |p| p.after_perform(*job_args) if p.respond_to?(:after_perform) }

        # Return true if the job was performed
        return job_was_performed

      # If an exception occurs during the job execution, look for an
      # on_failure hook then re-raise.
      rescue Object => e
        plugins.each { |p| p.on_failure(e, *job_args) if p.respond_to?(:on_failure) }
        raise
      end
    end

    # Returns the actual class constant represented in this job's payload.
    def payload_class
      @payload_class ||= constantize(@payload['class'])
    end

    # Returns an array of args represented in this job's payload.
    def args
      @payload['args']
    end

    # Given an exception object, hands off the needed parameters to
    # the Failure module.
    def fail(exception)
      Failure.create \
        :payload   => payload,
        :exception => exception,
        :worker    => worker,
        :queue     => queue
    end

    # Creates an identical job, essentially placing this job back on
    # the queue.
    def recreate
      self.class.create(queue, payload_class, *args)
    end

    # String representation
    def inspect
      obj = @payload
      "(Job{%s} | %s | %s)" % [ @queue, obj['class'], obj['args'].inspect ]
    end

    # Equality
    def ==(other)
      queue == other.queue &&
        payload_class == other.payload_class &&
        args == other.args
    end
  end
end
