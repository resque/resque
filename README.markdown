Resque
======

Resque creates and processes background jobs. It is heavily inspired
by DelayedJob, which rocks.

Resque is comprised of three parts:

1. Queues: FIFO queues for storing jobs to be processed
2. Workers: Persistent, distributed Ruby processes which do work
3. Frontend: A Sinatra app for monitoring queues and workers

We'll talk about each one in a moment.

A Brief History of Background Jobs
----------------------------------

We've used many different background job systems at GitHub. SQS,
Starling, ActiveMessaging, BackgroundJob, DelayedJob, and beanstalkd. 
Each change was out of necessity: we were running into a
limitation of the current system and needed to either fix it or move
to something designed with that limitation in mind.

With SQS, the limitation was latency. We were a young site and heard
stories on Amazon forums of multiple minute lag times between push and
pop. That is, once you put something on a queue you wouldn't be able
to get it back for what could be a while. That scared us so we moved.

ActiveMessaging was next, but only briefly. We wanted something
focused more on Ruby itself and less on libraries. That is, our jobs
should be Ruby classes or objects, whatever makes sense for our app,
and not subclasses of some framework's designed.

BackgroundJob (bj) was a perfect compromise: you could process Ruby
jobs or Rails jobs in the background. How you structured the jobs was
largely up to you. It even included priority levels, which would let
us make "repo create" and "fork" jobs run faster than the "warm some
caches" jobs.

However, bj loaded the entire Rails environment for each job. Loading
Rails is no small feat: it is CPU-expensive and takes a few
seconds. So for a job that may take less than a second, you could have
8 - 20s of added overhead depending on how big your app is, how many
dependencies it requires, and how bogged down your CPU is at that time.

DelayedJob (dj) fixed this problem: it is similar to bj, with a
database-backed queue and priorities, but its workers are
persitent. They only load Rails when started, then process jobs in a
loop. 

Jobs are just YAML-marshalled Ruby objects. With some magic you can
turn any method call into a job to be processed later.

Perfect. DJ lacked a few features we needed but we added them and
contributed the changes back.

We used DJ very successfully for a few months before running into some
issues. First: backed up queues. DJ works great with small datasets,
but once your site starts overloading and the queue backs up (to, say,
30,000 pending jobs) its queries become expensive. Creating jobs can
take 2s+ and acquiring locks on jobs can take 2s+, as well. This means
an added 2s per job created for each page load. On a page that fires
off two jobs, you're at a baseline of 4s before doing anything else.

If your queue is backed up because your site is overloaded, this added
overhead just makes the problem worse.

Solution: move to beanstalkd. beanstalkd is great because it's fast,
supports multiple queues, supports priorities, and speaks YAML
natively. A huge queue has constant time push and pop operations,
unlike a database-backed queue.

However, we quickly missed DJ features: seeing failed jobs, seeing
pending jobs (beanstalkd only allows you to 'peek' ahead at the next
pending job), manipulating the queue (e.g. running through and
removing all jobs that were created by a bug or with a bad job name),
etc. A database-queue gives you a lot of cool features. So we moved
back to DJ - the tradeoff was worth it.

Second: if a worker gets stuck, or is processing a job that will take
hours, DJ has facilities to release a lock and retry that job when
another worker is looking for work. But that stuck worker, even
though his work has been released, is still processing a job that you
most likely want to abort or fail.

You want that worker to fail or restart. We added code so that,
instead of simply retrying a job that failed due to timeout, other
workers will a) fail that job permanently then b) restart the locked
worker.

In a sense, all the workers were babysitting each other.

But what happens when all the workers are processing stuck or long
jobs? Your queue quickly backs up.

What you really need is a manager: someone like monit or god who can
watch workers and kill stale ones. 

Also, your workers will probably grow in memory a lot during the
course of their life. So you need to either make sure you never create
too many objects or "leak" memory, or you need to kill them when they
get too large (just like you do with your frontend web instances).

At this point we have workers processing jobs with god watching them
and killing any that are a) bloated or b) stale.

But how do we know all this is going on? How do we know what's sitting
on the queue? As I mentioned earlier, we had a web interface which
would show us pending items and try to infer how many workers are
working. But that's not easy - how do you have a worker you just 
`kill -9`'d gracefully manage its own state? We added a process to
inspect workers and add their info to memcached, which our web
frontend would then read from.

But who monitors that process. And do we have one running on each
server? This is quickly becoming very complicated.

Also we have another problem: startup time. There's a multi-second
startup cost when loading a Rails environment, not to mention the
added CPU time. With lots of workers doing lots of jobs being
restarted on a non-trival basis, that adds up.

It boils down to this: GitHub is a warzone. We are constantly
overloaded and rely very, very heavily on our queue. If it's backed
up, we need to know why. We need to know if we can fix it. We need
workers to not get stuck and we need to know when they are stuck.

We need to see what the queue is doing. We need to see what jobs have
failed. We need stats: how long are workers living, how many jobs are
they processing, how many jobs have been processed total, how many
errors have there been, are errors being repeated, did a deploy
introduce a new one?

We need a background job system as serious as our web
framework. I highly recommend DelayedJob to anyone whose site is not
50% background work.

But GitHub is 50% background work.

Resque to the Rescue
--------------------





Signals
-------

* `QUIT` - Wait for child to finish processing then exit
* `TERM` - Immediately kill child then exit
* `USR1` - Immediately kill child, don't exit
