module Resque
  # @see {Resque::JobPerformer#initialize}
  class JobPerformer
    attr_reader :job, :job_args, :hooks

    # @param payload_class [Class] - The class to call ::perform on
    # @param args [Array<Object>]  - An array of args to pass to the
    #                                payload_class::perform
    # @param hooks [Hash<Symbol,Array<String>]
    #                              - A hash with keys :before, :after and
    #                                :around, all arrays of methods to call
    #                                on the payload class with args
    def initialize(payload_class, args, hooks)
      @job      = payload_class
      @job_args = args || []
      @hooks    = hooks
    end

    # This is the actual performer for a single unit of work.  It's called
    # by Resque::Job#perform
    #
    # @return (see #performed?)
    def perform
      # before_hooks can raise a Resque::DontPerform exception
      # in which case we exit this method, returning false (because
      # the job was never performed)
      return false unless call_before_hooks
      execute_job
      call_hooks(:after)

      performed?
    end

    private

    # Calls the before hooks
    # @return [Boolean] a false return prevents the job from being performed.
    def call_before_hooks
      call_hooks(:before)
      true
    rescue Resque::DontPerform
      false
    end

    # Execute the job. Do it in an around_perform hook if available.
    # @return [void]
    def execute_job
      if hooks[:around].empty?
        perform_job
      else
        call_around_hooks
      end
    end

    # @return [void]
    def call_around_hooks
      nested_around_hooks.call
    end

    # We want to nest all around_perform plugins, with the last one
    # finally calling perform
    # @return [void]
    def nested_around_hooks
      final_hook = lambda { perform_job }
      hooks[:around].reverse.inject(final_hook) do |last_hook, hook|
        lambda { perform_hook(hook) { last_hook.call } }
      end
    end

    # @return [void]
    def call_hooks(hook_type)
      hooks[hook_type].each { |hook| perform_hook(hook) }
    end

    # @return [void]
    def perform_hook(hook, &block)
      job.__send__(hook, *job_args, &block)
    end

    # @return [Object] the result of job.perform(*job_args)
    def perform_job
      result = job.perform(*job_args)
      job_performed
      result
    end

    # @return [Boolean]
    def performed?
      @performed ||= false
    end

    # @return [true]
    def job_performed
      @performed = true
    end
  end
end
