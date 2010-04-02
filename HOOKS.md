Resque Hooks
============

You can customize Resque or write plugins using its hook API. In many
cases you can use a hook rather than mess with Resque's internals.

For a list of available plugins see
<http://wiki.github.com/defunkt/resque/plugins>.


Worker Hooks
------------

If you wish to have a Proc called before the worker forks for the
first time, you can add it in the initializer like so:

    Resque.before_first_fork do
      puts "Call me once before the worker forks the first time"
    end

You can also run a hook before _every_ fork:

    Resque.before_fork do |job|
      puts "Call me before the worker forks"
    end

The `before_fork` hook will be run in the **parent** process. So, be
careful - any changes you make will be permanent for the lifespan of
the worker.

And after forking:

    Resque.after_fork do |job|
      puts "Call me after the worker forks"
    end

The `after_fork` hook will be run in the child process and is passed
the current job. Any changes you make, therefor, will only live as
long as the job currently being processes.

All worker hooks can also be set using a setter, e.g.

    Resque.after_fork = proc { puts "called" }


Job Hooks
---------

Plugins can utilize job hooks to provide additional behavior. A job
hook is a method name in the following format:

    HOOKNAME_IDENTIFIER

For example, a `before_perform` hook which adds locking may be defined
like this:

    def before_perform_with_lock(*args)
      set_lock!
    end

Once this hook is made available to your job (either by way of
inheritence or `extend`), it will be run before the job's `perform`
method is called. Hooks of each type are executed in alphabetical order,
so `before_perform_a` will always be executed before `before_perform_b`.
An unnamed hook (`before_perform`) will be executed first.

The available hooks are:

* `before_perform`: Called with the job args before perform. If it raises
  `Resque::Job::DontPerform`, the job is aborted. If other exceptions
  are raised, they will be propagated up the the `Resque::Failure`
  backend.

* `after_perform`: Called with the job args after it performs. Uncaught
  exceptions will propagate up to the `Resque::Failure` backend.

* `around_perform`: Called with the job args. It is expected to yield in order
  to perform the job (but is not required to do so). It may handle exceptions
  thrown by `perform`, but any that are not caught will propagate up to the
  `Resque::Failure` backend.

* `on_failure`: Called with the exception and job args if any exception occurs
  while performing the job (or hooks).

Hooks are easily implemented with superclasses or modules. A superclass could
look something like this.

    class LoggedJob
      def self.before_perform_log_job(*args)
        Logger.info "About to perform #{self} with #{args.inspect}"
      end
    end

    class MyJob < LoggedJob
      def self.perform(*args)
        ...
      end
    end

Modules are even better because jobs can use many of them.

    module LoggedJob
      def before_perform_log_job(*args)
        Logger.info "About to perform #{self} with #{args.inspect}"
      end
    end

    module RetriedJob
      def on_failure_retry(e, *args)
        Logger.info "Performing #{self} caused an exception (#{e}). Retrying..."
        Resque.enqueue self, *args
      end
    end

    class MyJob
      extend LoggedJob
      extend RetriedJob
      def self.perform(*args)
        ...
      end
    end
