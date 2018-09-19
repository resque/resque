# Action Verb's Fork of Resque

Resque is awesome, and it's original README is available at its main
repository at https://github.com/resque/resque

We've used Resque in production for nearly 10 years, but we want to be
able to run millions of jobs per minute, so we've redesigned Resque
for enhanced performance.


## Acknowledgements and A Warning

First, a Huge Thank You to Chris Wanstrath and GitHub for all their work
on Resque thus far.  We are truly standing on the shoulders of giants
with this work.

As with most forks maintained by Action Verb, we've explictly removed
functionality not needed for our applications.  We find that it's easier
to take a radically new direction when we aren't encumbered by having to
support backwards compatibility.

If there is interest from the community, we are happy to work in
the future on re-introducing this functionality.

Many of the changes in this fork are experimental.  We use this fork in
production at Action Verb, but it has not been stress tested in the way
the original Resque code has been.


## Hybrid Process/Thread Model

We've moved the concurrency model of Resque to a three-tiered system.

There is now a Master Process, which forks off Worker Processes, which
run Worker Threads.

Each Worker Process regularly exits and is replaced by a new Worker
Process.  This preserves the original Resque behavior of memory
management while allowing additional scale.  In production we are able
to run thousands of jobs per FORK syscall, rather than the 1 job per
fork syscall that the stock Resque provides.

In addition to massively reducing the number of system calls required,
this structure also has the benefit of allowing a single Rake task to be
integrated to your system's service management infrastructure.


## Configuration

This fork adds a few new configuration variables, which are passed via
the ENV, just like stock Resque.

* `WORKER_COUNT` - default 1 - number of worker processes to run
* `THREAD_COUNT` - default 1 - number of threads to run per worker
  process
* `JOBS_PER_FORK` - default 1 - number of jobs to run each time a worker
  process is forked

The default values of 1/1/1 emulate stock Resque fairly well.  In
Production at Action Verb, we run a worker count equal to the number of
cores on the machine, a thread count of 4-16, and a `JOBS_PER_FORK`
of about 100-1000.


## Signals

Because workers now run multiple jobs at once, the signal responses have
been changed as well.

* TERM/INT: Shutdown immediately, kill current jobs immediately.
* QUIT: Shutdown after the current jobs have finished processing.
* USR1: Kill current jobs immediately, continue processing jobs.
* USR2: Don't process any new jobs
* CONT: Start processing jobs again after a USR2

If you want to gracefully shutdown a Resque worker, use `QUIT`.

If you want to stop processing jobs, but want to leave the worker running
(for example, to temporarily alleviate load), use `USR2` to stop processing,
then `CONT` to start it again.

If you want to kill stale or stuck job(s), use `USR2` to stop the
processing of new jobs.  Wait for the unstuck jobs to finish, then use
`USR1` to simultaneously kill the stuck job(s) and restart processing.

Signals sent to the Master Process will affect all Worker Processes and
Worker Threads.  Signals sent to a specific Worker Process will affect
that Worker Process only.


## Internal Changes

The Worker class was being overloaded to refer to both an active worker
(parent and child) and the representation of a worker on another machine
when viewing the Web UI.  This has been detangled.  We now have a
Worker, WorkerThread, WorkerManager, and WorkerStatus.
