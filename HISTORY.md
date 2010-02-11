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
