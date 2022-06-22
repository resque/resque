Resque Hooks
============

You can customize Resque or write plugins using its hook API. In many
cases you can use a hook rather than mess with Resque's internals.

For a list of available plugins see
<https://github.com/resque/resque/wiki/plugins>.


Worker Hooks
------------

If you wish to have a Proc called before the worker forks for the
first time, you can add it in the initializer like so:

``` ruby
Resque.before_first_fork do
  puts "Call me once before the worker forks the first time"
end
```

You can also run a hook before _every_ fork:

``` ruby
Resque.before_fork do |job|
  puts "Call me before the worker forks"
end
```

The `before_fork` hook will be run in the **parent** process. So, be
careful - any changes you make will be permanent for the lifespan of
the worker.

And after forking:

``` ruby
Resque.after_fork do |job|
  puts "Call me after the worker forks"
end
```

The `after_fork` hook will be run in the child process and is passed
the current job. Any changes you make, therefore, will only live as
long as the job currently being processes.

All worker hooks can also be set using a setter, e.g.

``` ruby
Resque.after_fork = proc { puts "called" }
```

When the worker finds no more jobs in the queue:

``` ruby
Resque.queue_empty do
  puts "Call me whenever the worker becomes idle"
end
```

The `queue_empty` hook will be run in the **parent** process.

When the worker exits:

``` ruby
Resque.worker_exit do
  puts "Call me when the work is about to terminate"
end
```

The `worker_exit` hook will be run in the **parent** process.

Workers can also take advantage of running any code defined using Ruby's `at_exit` block by setting
`ENV["RUN_AT_EXIT_HOOKS"]=1`. By default, this is turned off. Be advised that setting this value might execute
code from gems which register their own `at_exit` hooks.

Job Hooks
---------

Plugins can utilize job hooks to provide additional behavior. A job
hook is a method name in the following format:

    HOOKNAME_IDENTIFIER

For example, a `before_perform` hook which adds locking may be defined
like this:

``` ruby
def before_perform_with_lock(*args)
  set_lock!
end
```

Once this hook is made available to your job (either by way of
inheritence or `extend`), it will be run before the job's `perform`
method is called. Hooks of each type are executed in alphabetical order,
so `before_perform_a` will always be executed before `before_perform_b`.
An unnamed hook (`before_perform`) will be executed first.

The available hooks are:

* `before_enqueue`: Called with the job args before a job is placed on the queue.
  If the hook returns `false`, the job will not be placed on the queue.

* `after_enqueue`: Called with the job args after a job is placed on the queue.
  Any exception raised propagates up to the code which queued the job.

* `before_dequeue`: Called with the job args before a job is removed from the queue.
  If the hook returns `false`, the job will not be removed from the queue.

* `after_dequeue`: Called with the job args after a job was removed from the queue.
  Any exception raised propagates up to the code which dequeued the job.

* `before_perform`: Called with the job args before perform. If it raises
  `Resque::Job::DontPerform`, the job is aborted. If other exceptions
  are raised, they will be propagated up the the `Resque::Failure`
  backend.

* `after_perform`: Called with the job args after it performs. Uncaught
  exceptions will propagate up to the `Resque::Failure` backend. *Note: If the job fails, `after_perform` hooks will not be run.*

* `around_perform`: Called with the job args. It is expected to yield in order
  to perform the job (but is not required to do so). It may handle exceptions
  thrown by `perform`, but any that are not caught will propagate up to the
  `Resque::Failure` backend.

* `on_failure`: Called with the exception and job args if any exception occurs
  while performing the job (or hooks), this includes Resque::DirtyExit.

Hooks are easily implemented with superclasses or modules. A superclass could
look something like this.

``` ruby
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
```

Modules are even better because jobs can use many of them.

``` ruby
module ScaledJob
  def after_enqueue_scale_workers(*args)
    Logger.info "Scaling worker count up"
    Scaler.up! if Resque.info[:pending].to_i > 25
  end
end

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
  extend ScaledJob
  def self.perform(*args)
    ...
  end
end
```
