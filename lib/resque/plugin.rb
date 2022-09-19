module Resque
  module Plugin
    extend self

    @job_methods = {}
    def job_methods(job)
      @job_methods[job] ||= job.methods.collect{|m| m.to_s}
    end

    # Given an object, and a method prefix, returns a list of methods prefixed
    # with that name (hook names).
    def get_hook_names(job, hook_method_prefix)
      methods = (job.respond_to?(:hooks) && job.hooks) || job_methods(job)
      methods.select{|m| m.start_with?(hook_method_prefix)}.sort
    end

    # Given an object, returns a list `before_perform` hook names.
    def before_hooks(job)
      get_hook_names(job, 'before_perform_')
    end

    # Given an object, returns a list `around_perform` hook names.
    def around_hooks(job)
      get_hook_names(job, 'around_perform_')
    end

    # Given an object, returns a list `after_perform` hook names.
    def after_hooks(job)
      get_hook_names(job, 'after_perform_')
    end

    # Given an object, returns a list `on_failure` hook names.
    def failure_hooks(job)
      get_hook_names(job, 'on_failure_')
    end

    # Given an object, returns a list `after_enqueue` hook names.
    def after_enqueue_hooks(job)
      get_hook_names(job, 'after_enqueue_')
    end

    # Given an object, returns a list `before_enqueue` hook names.
    def before_enqueue_hooks(job)
      get_hook_names(job, 'before_enqueue_')
    end

    # Given an object, returns a list `after_dequeue` hook names.
    def after_dequeue_hooks(job)
      get_hook_names(job, 'after_dequeue_')
    end

    # Given an object, returns a list `before_dequeue` hook names.
    def before_dequeue_hooks(job)
      get_hook_names(job, 'before_dequeue_')
    end
  end
end
