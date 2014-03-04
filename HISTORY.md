## 1.25.2 (TBD)

* Respect TERM_CHILD setting when not forking (@ggilder)
* implementation of backend connection with a hash (Andrea Rossi)
* require yaml for show_args support (@yaauie)
* use redis-namespace 1.3 (Andrea Rossi)
* fix DOCS link in README (@cade)
* Fix worker prune test to actually run its assertion & cover reality. (@yaauie)
* Eliminate infinite recursion when Resque::Helpers mixed into Resque (@yaml)
* use ruby, avoid shelling out. google++ (@hone)
* Failed Assertions Don't Fail Tests :rage: (@yaauie)

## 1.25.1 (2013-9-26)

* Actually require Forwardable from the standard library.

## 1.25.0 (TBD)
* Updates fork method so [resque-multi-job-forks](https://github.com/stulentsev/resque-multi-job-forks)
  monkey patching works again. See discussion at https://github.com/defunkt/resque/pull/895 for more
  context (@jonhyman)
* Use Redis.pipelined to group batches of redis commands.
  https://github.com/resque/resque/pull/902 (@jonhyman)
* Fixed uninitialize constant for the module/class that contains the perform
  method causing job failures to no be reported, #792 (@sideshowcoder)
* Fix Resque::Failure::Base.all to have the correct signature.
  (@rentalutions)
* Don't close stdio pipes when daemonizing so as to not hide errors. #967
  (@sideshowcoder)
* Fix for worker_pids on Windows. #980 (@kzgs)
* Only prune workers for queues the current worker knows about. #1000
  (!) (@dsabanin)
* Handle duplicate TERM signals. #988 (@softwaregravy)
* Fix issue with exiting workers and unintentionally deregistering the
  parent when the forked child exits. #1017 (@magec)
* Fix encoding errors with local date formatting. #1065 (@katafrakt)
* Fix CI for 1.8.7 and 1.9.2 modes due to dependencies. #1090
  (@adelcambre)
* Allow using globs for queue names to listen on, allowing things like
  listening on `staging_*`. #1085 (@adelcambre)


## 1.24.1 (2013-3-23)

* Adds a default value for `per_page` on resque-server for plugins which add tabs (@jonhyman)
* Fix bad logic on the failed queue adapter
* Added missing `require 'time'` which was causing occasional errors which
  would crash workers.

## 1.24.0 (2013-3-21)

* Web UI: Fix regression that caused the failure tab to break when using
  certain failure backends (@kjg)
* Web UI: Add page list to queues (@ql)
* Web UI: Fix regression that caused the failure tab to break when clicking on
  "clear all failures" under certain failure backends, #859 (@jonhyman)
* Fix regression for Resque hooks where Resque would error out if you assigned
  multiple hooks using an array, #859 (@jonhyman)
* Adds ENV["RUN_AT_EXIT_HOOKS"] which when set to 1 causes any defined
  `at_exit` hooks to be run on the child when the forked process exits, #862
  (@jonhyman)
* Bump up redis-namespace to 1.2.
* Remove multi_json, the JSON gem does the right thing everywhere now.
* Documentation fixes with demo instructions.
* Fixed encoding for worker PIDs on Windows (@kzgs)
* Cache value of PID in an ivar. This way, if you try to look up worker PIDs
  from some other process (such as the console), they will be correct.
* Add a mutex-free logger. Ruby 2.0 does not allow you to use a mutex from
  a signal handler, which can potentially cause deadlock. Now we're using
  `mono_logger`, which has no locks.

## 1.23.1 (2013-3-7)

* JRuby and Rubinius are 'allow failure' on CI. This is largely due to Travis
  weridness and flaky tests.
* Fix link from "queues" view to "failed" view when there's only one failed
  queue (trliner)
* Making all the failure backends have the same method signature for duck
  typing purposes (jonhyman)
* Fix log formatters not appending a new line (flavorpill)
* redirect unauthorized resque-web polling requests to root url (trliner)
* Various resque-web fixes (@tarcieri)
* Optional RedisMultiQueue failure backend, can be enabled with
  FAILURE_BACKEND=redis_multi_queue env var (@tarcieri)
* resque:failures:sort rake task will migrate an existing "failed" queue into
  separate failure queues per job queue, allowing an easy migration to
  the RedisMultiQueue failure backend (@tarcieri)
* Disable forking completely with FORK_PER_JOB=false env var (@tarcieri)
* Report a failure when processes are killed with signals (@dylanahsmith)
* Enable registering of multiple Resque hooks (@panthomakos, @jonhyman)

## 1.23.0 (2012-10-01)

* don't run `before_fork` hook if Resque can't fork (@kjwierenga, @tarcieri, #672, #697)
* don't run `after_fork` hook if Resque can't fork (@kjwierenga, @tarcieri, #672, #697)
* retry connecting to redis up to 3 times (@trevorturk, #693)
* pass exceptions raised by the worker into the Failure backend (@trevorturk, #693)

## 1.22.0 (2012-08-21)

* unregister signal handlers in child process when ENV["TERM_CHILD"] is set (@dylanasmith, #621)
* new signal handling for TERM. See http://hone.heroku.com/resque/2012/08/21/resque-signals.html. (@wuputah, @yaaule, #638)
* supports calling perform hooks when using Resque.inline (@jonhyman, #506)

## 1.21.0 (2012-07-02)

* Add a flag to make sure failure hooks are only ran once (jakemack, #546)
* Support updated MultiJSON API (@twinturbo)
* Fix worker logging in monit example config (@twinturbo)
* loosen dependency of redis-namespace to 1.x, support for redis-rb 3.0.x
* change '%' to '$' in the 'stop program' command for monit
* UTF8 sanitize exception messages when there's a failure (@brianmario, #507)
* don't share a redis connection between parent and child (@jsanders, #588)

## 1.20.0 (2012-02-17)

* Fixed demos for ruby 1.9 (@BMorearty, #445)
* Fixed `#requeue` tests (@hone, #500)
* Web UI: optional trailing slashes of URLs (@elisehuard, #449)
* Allow * to appear anywhere in queue list (@tapajos, #405, #407)
* Wait for child with specific PID (@jacobkg)
* #decode raise takes a string when re-raising as a different exception class (Trevor Hart)
* Use Sinatra's `pubilc_folder` if it exists (@defunkt, #420, #421)
* Assign the job's worker before calling `before_fork` (@quirkey)
* Fix Resque::Helpers#constantize to work correctly on 1.9.2 (@rtlong)
* Added before & after hooks for dequeue (@humancopy, #398)
* daemonize support using `ENV["BACKGROUND"]` (@chrisleishman)
* requeue and remove failed jobs by queue name (@evanwhalen)
* `-r` flag for resque-web for redis connection (@gjastrab)
* Added `Resque.enqueue_to`: allows you to specif the queue and still run hooks (@dan-g)
* Web UI: Set the default encoding to UTF-8 (@elubow)
* fix finding worker pids on JRuby (John Andrews + Andrew Grieser)
* Added distributed redis support (@stipple)
* Added better failure hooks (@raykrueger)
* Added before & after dequeue hooks (@humancopy)

## 1.19.0 (2011-09-01)

* Added Airbrake (formerly Hoptoad) support.
* Web UI: Added retry all button to failed jobs page
* Web UI: Show focus outline

## 1.18.6 (2011-08-30)

* Bugfix: Use Rails 3 eager loading for resque:preload

## 1.18.5 (2011-08-24)

* Added support for Travis CI
* Bugfix: preload only happens in production Rails environment

## 1.18.4 (2011-08-23)

* Bugfix: preload task depends on setup

## 1.18.3 (2011-08-23)

* Bugfix: Fix preloading on Rails 3.x.

## 1.18.2 (2011-08-19)

* Fix RAILS_ROOT deprecation warning

## 1.18.1 (2011-08-19)

* Bugfix: Use RAILS_ROOT in preload task

## 1.18.0 (2011-08-18)

* Added before_enqueue hook.
* Resque workers now preload files under app/ in Rails
* Switch to MultiJSON
* Bugfix: Finding worker pids on Solaris
* Web UI: Fix NaN days ago for worker screens
* Web UI: Add Cache-Control header to prevent proxy caching
* Web UI: Update Resque.redis_id so it can be used in a distributed ring.

## 1.17.1 (2011-05-27)

* Reverted `exit` change. Back to `exit!`.

## 1.17.0 (2011-05-26)

* Workers exit with `exit` instead of `exit!`. This means you
  can now use `at_exit` hooks inside workers.
* More monit typo fixes.
* Fixed bug in Hoptoad backend.
* Web UI: Wrap preformatted arguments.

## 1.16.1 (2011-05-17)

* Bugfix: Resque::Failure::Hoptoad.configure works again
* Bugfix: Loading rake tasks

## 1.16.0 (2011-05-16)

* Optional Hoptoad backend extracted into hoptoad_notifier. Install the gem to use it.
* Added `Worker#paused?` method
* Bugfix: Properly reseed random number generator after forking.
* Bugfix: Resque.redis=(<a Redis::Namespace>)
* Bugfix: Monit example stdout/stderr redirection
* Bugfix: Removing single failure now works with multiple failure backends
* Web: 'Remove Queue' now requires confirmation
* Web: Favicon!
* Web Bugfix: Dates display in Safari
* Web Bugfix: Dates display timezone
* Web Bugfix: Race condition querying working workers
* Web Bugfix: Fix polling /workers/all in resque-web

## 1.15.0 (2011-03-18)

* Fallback to Redis.connect. Makes ENV variables and whatnot work.
* Fixed Sinatra 1.2 compatibility

## 1.14.0 (2011-03-17)

* Sleep interval can now be a float
* Added Resque.inline to allow in-process performing of jobs (for testing)
* Fixed tests for Ruby 1.9.2
* Added Resque.validate(klass) to validate a Job
* Decode errors are no longer ignored to help debugging
* Web: Sinatra 1.2 compatibility
* Fixed after_enqueue hook to actually run in `Resque.enqueue`
* Fixed very_verbose timestamps to use 24 hour time (AM/PM wasn't included)
* Fixed monit example
* Fixed Worker#pid

## 1.13.0 (2011-02-07)

* Depend on redis-namespace >= 0.10
* README tweaks
* Use thread_safe option when setting redis url
* Bugfix: worker pruning

## 1.12.0 (2011-02-03)

* Added pidfile writing from `rake resque:work`
* Added Worker#pid method
* Added configurable location for `rake install`
* Bugfix: Errors in failure backend are rescue'd
* Bugfix: Non-working workers no longer counted in "working" count
* Bugfix: Don't think resque-web is a worker

## 1.11.0 (2010-08-23)

* Web UI: Group /workers page by hostnames

## 1.10.0 (2010-08-23)

* Support redis:// string format in `Resque.redis=`
* Using new cross-platform JSON gem.
* Added `after_enqueue` plugin hook.
* Added `shutdown?` method which can be overridden.
* Added support for the "leftright" gem when running tests.
* Grammarfix: In the README

## 1.9.10 (2010-08-06)

* Bugfix: before_fork should get passed the job

## 1.9.9 (2010-07-26)

* Depend on redis-namespace 0.8.0
* Depend on json_pure instead of json (for JRuby compat)
* Bugfix: rails_env display in stats view

## 1.9.8 (2010-07-20)

* Bugfix: Worker.all should never return nil
* monit example: Fixed Syntax Error and adding environment to the rake task
* redis rake task: Fixed typo in copy command

## 1.9.7 (2010-07-09)

* Improved memory usage in Job.destroy
* redis-namespace 0.7.0 now required
* Bugfix: Reverted $0 changes
* Web Bugfix: Payload-less failures in the web ui work

## 1.9.6 (2010-06-22)

* Bugfix: Rakefile logging works the same as all the other logging

## 1.9.5 (2010-06-16)

* Web Bugfix: Display the configured namespace on the stats page
* Revert Bugfix: Make ps -o more cross platform friendly

## 1.9.4 (2010-06-14)

* Bugfix: Multiple failure backend gets exception information when created

## 1.9.3 (2010-06-14)

* Bugfix: Resque#queues always returns an array

## 1.9.2 (2010-06-13)

* Bugfix: Worker.all returning nil fix
* Bugfix: Make ps -o more cross platform friendly

## 1.9.1 (2010-06-04)

* Less strict JSON dependency
* Included HISTORY.md in gem

## 1.9.0 (2010-06-04)

* Redis 2 support
* Depend on redis-namespace 0.5.0
* Added Resque::VERSION constant (alias of Resque::Version)
* Bugfix: Specify JSON dependency
* Bugfix: Hoptoad plugin now works on 1.9

## 1.8.5 (2010-05-18)

* Bugfix: Be more liberal in which Redis clients we accept.

## 1.8.4 (2010-05-18)

* Try to resolve redis-namespace dependency issue

## 1.8.3 (2010-05-17)

* Depend on redis-rb ~> 1.0.7

## 1.8.2 (2010-05-03)

* Bugfix: Include "tasks/" dir in RubyGem

## 1.8.1 (2010-04-29)

* Bugfix: Multiple failure backend did not support requeue-ing failed jobs
* Bugfix: Fix /failed when error has no backtrace
* Bugfix: Add `Redis::DistRedis` as a valid client

## 1.8.0 (2010-04-07)

* Jobs that never complete due to killed worker are now failed.
* Worker "working" state is now maintained by the parent, not the child.
* Stopped using deprecated redis.rb methods
* `Worker.working` race condition fixed
* `Worker#process` has been deprecated.
* Monit example fixed
* Redis::Client and Redis::Namespace can be passed to `Resque.redis=`

## 1.7.1 (2010-04-02)

* Bugfix: Make job hook execution order consistent
* Bugfix: stdout buffering in child process

## 1.7.0 (2010-03-31)

* Job hooks API. See docs/HOOKS.md.
* web: Hovering over dates shows a timestamp
* web: AJAXify retry action for failed jobs
* web bugfix: Fix pagination bug

## 1.6.1 (2010-03-25)

* Bugfix: Workers may not be clearing their state correctly on
  shutdown
* Added example monit config.
* Exception class is now recorded when an error is raised in a
  worker.
* web: Unit tests
* web: Show namespace in header and footer
* web: Remove a queue
* web: Retry failed jobs

## 1.6.0 (2010-03-09)

* Added `before_first_fork`, `before_fork`, and `after_fork` hooks.
* Hoptoad: Added server_environment config setting
* Hoptoad bugfix: Don't depend on RAILS_ROOT
* 1.8.6 compat fixes

## 1.5.2 (2010-03-03)

* Bugfix: JSON check was crazy.

## 1.5.1 (2010-03-03)

* `Job.destroy` and `Resque.dequeue` return the # of destroyed jobs.
* Hoptoad notifier improvements
* Specify the namespace with `resque-web` by passing `-N namespace`
* Bugfix: Don't crash when trying to parse invalid JSON.
* Bugfix: Non-standard namespace support
* Web: Red backgound for queue "failed" only shown if there are failed jobs.
* Web bugfix: Tabs highlight properly now
* Web bugfix: ZSET partial support in stats
* Web bugfix: Deleting failed jobs works again
* Web bugfix: Sets (or zsets, lists, etc) now paginate.

## 1.5.0 (2010-02-17)

* Version now included in procline, e.g. `resque-1.5.0: Message`
* Web bugfix: Ignore idle works in the "working" page
* Added `Resque::Job.destroy(queue, klass, *args)`
* Added `Resque.dequeue(klass, *args)`

## 1.4.0 (2010-02-11)

* Fallback when unable to bind QUIT and USR1 for Windows and JRuby.
* Fallback when no `Kernel.fork` is provided (for IronRuby).
* Web: Rounded corners in Firefox
* Cut down system calls in `Worker#prune_dead_workers`
* Enable switching DB in a Redis server from config
* Support USR2 and CONT to stop and start job processing.
* Web: Add example failing job
* Bugfix: `Worker#unregister_worker` shouldn't call `done_working`
* Bugfix: Example god config now restarts Resque properly.
* Multiple failure backends now permitted.
* Hoptoad failure backend updated to new API

## 1.3.1 (2010-01-11)

* Vegas bugfix: Don't error without a config

## 1.3.0 (2010-01-11)

* Use Vegas for resque-web
* Web Bugfix: Show proper date/time value for failed_at on Failures
* Web Bugfix: Make the / route more flexible
* Add Resque::Server.tabs array (so plugins can add their own tabs)
* Start using [Semantic Versioning](http://semver.org/)

## 1.2.4 (2009-12-15)

* Web Bugfix: fix key links on stat page

## 1.2.3 (2009-12-15)

* Bugfix: Fixed `rand` seeding in child processes.
* Bugfix: Better JSON encoding/decoding without Yajl.
* Bugfix: Avoid `ps` flag error on Linux
* Add `PREFIX` observance to `rake` install tasks.

## 1.2.2 (2009-12-08)

* Bugfix: Job equality was not properly implemented.

## 1.2.1 (2009-12-07)

* Added `rake resque:workers` task for starting multiple workers.
* 1.9.x compatibility
* Bugfix: Yajl decoder doesn't care about valid UTF-8
* config.ru loads RESQUECONFIG if the ENV variable is set.
* `resque-web` now sets RESQUECONFIG
* Job objects know if they are equal.
* Jobs can be re-queued using `Job#recreate`

## 1.2.0 (2009-11-25)

* If USR1 is sent and no child is found, shutdown.
* Raise when a job class does not respond to `perform`.
* Added `Resque.remove_queue` for deleting a queue

## 1.1.0 (2009-11-04)

* Bugfix: Broken ERB tag in failure UI
* Bugfix: Save the worker's ID, not the worker itself, in the failure module
* Redesigned the sinatra web interface
* Added option to clear failed jobs

## 1.0.0 (2009-11-03)

* First release.
