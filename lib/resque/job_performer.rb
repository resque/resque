module Resque
  class JobPerformer
    attr_reader :job, :job_args, :hooks

    # This is the actual performer for a single unit of work.  It's called
    # by Resque::Job#perform
    # Args:
    #   palyoad_class: The class to call ::perform on
    #   args: An array of args to pass to the payload_class::perform
    #   hook: A hash with keys :before, :after and :around, all arrays of
    #         methods to call on the payload class with args
    def perform(payload_class, args, hooks)
      # Setup instance variables for the helper methods
      @job      = payload_class
      @job_args = args || []
      @hooks    = hooks

      # Before hooks can raise a Resque::DontPerform exception
      # in which case we exit this method, returning false (because
      # the job was never performed)
      return false unless call_before_hooks
      execute_job
      call_hooks(:after)

      # Return whether or not the job was performed
      performed?
    end

    private
    def call_before_hooks
      begin
        call_hooks(:before)
        true
      rescue Resque::DontPerform
        false
      end
    end

    def execute_job
      # Execute the job. Do it in an around_perform hook if available.
      if hooks[:around].empty?
        perform_job
      else
        call_around_hooks
      end
    end

    def call_around_hooks
      nested_around_hooks.call
    end

    # We want to nest all around_perform plugins, with the last one
    # finally calling perform
    def nested_around_hooks
      final_hook = lambda { perform_job }
      hooks[:around].reverse.inject(final_hook) do |last_hook, hook|
        lambda { perform_hook(hook) { last_hook.call } }
      end
    end

    def call_hooks(hook_type)
      hooks[hook_type].each { |hook| perform_hook(hook) }
    end

    def perform_hook(hook, &block)
      job.__send__(hook, *job_args, &block)
    end

    def perform_job
      result = job.perform(*job_args)
      job_performed
      result
    end

    def performed?
      @performed ||= false
    end

    def job_performed
      @performed = true
    end
  end
end
