module Resque
  # A registry for hooks that are applied to jobs at various stages
  # of their execution.
  # @see {docs/HOOKS.md}
  class HookRegister
    # @private
    def initialize
      @hooks = {}
    end

    # The `before_first_fork` hook will be run in the **parent** process
    # only once, before forking to run the first job. Be careful- any
    # changes you make will be permanent for the lifespan of the
    # worker.
    #
    # Call with a block to register a hook.
    # Call with no arguments to return all registered hooks.
    # @overload method()
    #   Return the existing method hooks
    #   @return (see #hooks)
    # @overload method(&block)
    #   @return (see #register_hook)
    def before_first_fork(&block)
      block ? register_hook(:before_first_fork, block) : hooks(:before_first_fork)
    end

    # Register a before_first_fork proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def before_first_fork=(block)
      register_hook(:before_first_fork, block)
    end

    # The `before_fork` hook will be run in the **parent** process
    # before every job, so be careful- any changes you make will be
    # permanent for the lifespan of the worker.
    #
    # Call with a block to register a hook.
    # Call with no arguments to return all registered hooks.
    # @overload method()
    #   Return the existing method hooks
    #   @return (see #hooks)
    # @overload method(&block)
    #   @return (see #register_hook)
    def before_fork(&block)
      block ? register_hook(:before_fork, block) : hooks(:before_fork)
    end

    # Register a before_fork proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def before_fork=(block)
      register_hook(:before_fork, block)
    end

    # The `after_fork` hook will be run in the child process and is passed
    # the current job. Any changes you make, therefore, will only live as
    # long as the job currently being processed.
    #
    # Call with a block to register a hook.
    # Call with no arguments to return all registered hooks.
    # @overload method()
    #   Return the existing method hooks
    #   @return (see #hooks)
    # @overload method(&block)
    #   @return (see #register_hook)
    def after_fork(&block)
      block ? register_hook(:after_fork, block) : hooks(:after_fork)
    end

    # Register an after_fork proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def after_fork=(block)
      register_hook(:after_fork, block)
    end

    # The `before_pause` hook will be run in the parent process before the
    # worker has paused processing (via #pause_processing or SIGUSR2).
    # @overload before_pause()
    #   Return the existing before_pause hooks
    #   @return (see #hooks)
    # @overload before_pause(&block)
    #   @return (see #register_hook)
    def before_pause(&block)
      block ? register_hook(:before_pause, block) : hooks(:before_pause)
    end

    # Register a before_pause proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def before_pause=(block)
      register_hook(:before_pause, block)
    end

    # The `after_pause` hook will be run in the parent process after the
    # worker has paused (via SIGCONT).
    # @overload after_pause()
    #   Return the existing after_pause hooks
    #   @return (see #hooks)
    # @overload after_pause(&block)
    #   @return (see #register_hook)
    def after_pause(&block)
      block ? register_hook(:after_pause, block) : hooks(:after_pause)
    end

    # Register an after_pause proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def after_pause=(block)
      register_hook(:after_pause, block)
    end

    # The `before_perform` hook will be run in the child process before
    # the job code is performed. This hook will run before any
    # Job.before_perform hook.
    #
    # Call with a block to register a hook.
    # Call with no arguments to return all registered hooks.
    # @overload before_perform()
    #   Return the existing before_perform hooks
    #   @return (see #hooks)
    # @overload before_perform(&block)
    #   @return (see #register_hook)
    def before_perform(&block)
      block ? register_hook(:before_perform, block) : hooks(:before_perform)
    end

    # Register an before_perform proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def before_perform=(block)
      register_hook(:before_perform, block)
    end

    # The `after_perform` hook will be run in the child process after
    # the job code has performed. This hook will run after any
    # Job.after_perform hook.
    #
    # Call with a block to register a hook.
    # Call with no arguments to return all registered hooks.
    # @overload after_perform()
    #   Return the existing after_perform hooks
    #   @return (see #hooks)
    # @overload after_perform(&block)
    #   @return (see #register_hook)
    def after_perform(&block)
      block ? register_hook(:after_perform, block) : hooks(:after_perform)
    end

    # Register an after_perform proc.
    # @param block (see #register_hook)
    # @return (see #register_hook)
    def after_perform=(block)
      register_hook(:after_perform, block)
    end


    private


    # Register a new proc as a hook. If the block is nil this is the
    # equivalent of removing all hooks of the given name.
    #
    # @param name [Symbol] - the hook that the block should be registered with.
    # @param block [#call] - the block to be executed when the hooked event occurs.
    # @return [Array<#call>] all registered hooks for this name
    def register_hook(name, block)
      return clear_hooks(name) if block.nil?

      @hooks ||= {}
      @hooks[name] ||= []

      block = Array(block)
      @hooks[name].concat(block)
    end

    # Clear all hooks given a hook name.
    # @param name [Symbol]
    # @return [void]
    def clear_hooks(name)
      @hooks && @hooks[name] = []
    end

    # Retrieve all hooks of a given name, or all hooks if name.nil?
    # @overload hooks(name)
    #   Retrieve all hooks of a given name
    #   @param name [Symbol]
    #   @return [Array<#call>]
    # @overload hooks()
    #   Retrieve all hooks
    #   @return [Hash<Symbol,Array<#call>>]
    def hooks(name = nil)
      if name
        (@hooks && @hooks[name]) || []
      else
        @hooks
      end
    end
  end
end
