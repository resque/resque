Resque
======

Resque is a Redis-backed library for creating background jobs, placing
those jobs on multiple queues, and processing them later.

Background jobs can be any Ruby class or module that responds to
`perform`. Your existing classes can easily be converted to background
jobs or you can create new classes specifically to do work. Or, you
can do both.

Resque is heavily inspired by DelayedJob (which rocks) and is
comprised of three parts:

1. A Ruby library for creating, querying, and processing jobs
2. A Rake task for starting a worker which processes jobs
3. A Sinatra app for monitoring queues, jobs, and workers.

Resque workers can be distributed between multiple machines,
support priorities, are resililent to memory bloat / "leaks," are
optimized for REE (but work on MRI and JRuby), tell you what they're
doing, and expect failure.

Resque queues are persistent; support constant time, atomic push and
pop (thanks to Redis); provide visibility into their contents; and
store jobs as simple JSON packages.

The Resque frontend tells you what workers are doing, what workers are
not doing, what queues you're using, what's in those queues, provides
general usage stats, and helps you track failures.


The Blog Post
-------------

For the backstory, philosophy, and history of Resque's beginnings,
please see [the blog post][0].


Overview
--------

Resque allows you to create jobs and place them on a queue, then,
later, pull those jobs off the queue and process them.

Resque jobs are Ruby classes (or modules) which respond to the
`perform` method. Here's an example:

    class Archive
      @queue = :file_serve
      
      def self.perform(repo_id, branch = 'master')
        repo = Repository.find(repo_id)
        repo.create_archive(branch)
      end
    end

The `@queue` class instance variable determines which queue `Archive`
jobs will be placed in. Queues are arbitrary and created on the fly -
you can name them whatever you want and have as many as you want.

To place an `Archive` job on the `file_serve` queue, we might add this
to our application's pre-existing `Repository` class:

    class Repository
      def async_create_archive(branch)
        Resque.enqueue(Archive, self.id, branch)
      end
    end

Now when we call `repo.async_create_archive('masterbrew')` in our
application, a job will be created and placed on the `file_serve`
queue.

Later, a worker will run something like this code to process the job:
  
    klass, args = Resque.reserve(:file_serve)
    klass.perform(*args) if klass.respond_to? :perform

Which translates to:
   
    Archive.perform(44, 'masterbrew')

Let's start a worker to run `file_serve` jobs:

    $ cd app_root
    $ QUEUE=file_serve rake resque:work

This starts one Resque worker and tells it to work off the
`file_serve` queue. As soon as it's ready it'll try to run the
`Resque.reserve` code snippet above and process jobs until it can't
find any more, at which point it will sleep for a small period and
repeatedly poll the queue for more jobs.

Workers can be given multiple queues (a "queue list") and run on
multiple machines. In fact they can be run anywhere with network
access to the Redis server.


Jobs
----

What should you run in the background? Anything that takes any time at
all. Slow INSERT statements, disk manipulating, data processing, etc.

At GitHub we use Resque to process the following types of jobs:

* Warming caches
* Counting disk usage
* Building tarballs
* Building Rubygems
* Firing off web hooks
* Creating events in the db and pre-caching them
* Building graphs
* Deleting users
* Updating our search index

As of writing we have about 35 different types of background jobs.

Keep in mind that you don't need a web app to use Resque - we just
mention "foreground" and "background" because they make conceptual
sense. You could easily be spidering sites and sticking data which
needs to be crunched later into a queue.


### Persistence

Jobs are persisted to queues as JSON objects. Let's take our `Archive`
example from above. We'll run the following code to create a job:

    repo = Repository.find(44)
    repo.async_create_archive('masterbrew')

The following JSON will be stored in the `file_serve` queue:

    {
        'class': 'Archive',
        'args': [ 44, 'masterbrew' ]
    }

Because of this your jobs must only accept arguments that can be JSON encoded.

So instead of doing this:

    Resque.enqueue(Archive, self, branch)  

do this:

    Resque.enqueue(Archive, self.id, branch)
    
This is why our above example (and all the examples in `examples/`)
uses object IDs instead of passing around the objects.

While this is less convenient than just sticking a marshalled object
in the database, it gives you a slight advantage: your jobs will be
run against the most recent version of an object because they need to
pull from the DB or cache.

If your jobs were run against marshalled objects, they could
potentially be operating on a stale record with out-of-date information.


### send_later / async

Want something like DelayedJob's `send_later` or the ability to use
instance methods instead of just methods for jobs? See the `examples/`
directory for goodies.

We plan to provide first class `async` support in a future release.


### Failure

If a job raises an exception, it is logged and handed off to the
`Resque::Failure` module. Failures are logged either locally in Redis
or using some different backend.

For example, Resque ships with Hoptoad and GetException support.

Keep this in mind when writing your jobs: you may want to throw
exceptions you would not normally throw in order to assist debugging.


Workers
-------

Resque workers are rake tasks the run forever. They basically do this:

    start
    loop do
      if job = reserve
        job.process
      else
        sleep 5
      end
    end
    shutdown

Starting a worker is simple. Here's our example from earlier:

    $ QUEUE=file_serve rake resque:work

By default Resque won't know about your application's
environment. That is, it won't be able to find and run your jobs - it
needs to load your application into memory.

If we've installed Resque as a Rails plugin, we might run this command
from our RAILS_ROOT:

    $ QUEUE=file_serve rake environment resque:work

This will load the environment before starting a worker. Alternately
we can define a `resque:setup` task with a dependency on the
`environment` rake task:

    task "resque:setup" => :environment


### Priorities


### Forking

When a Resque worker g


### Signals

Resque workers respond to a few different signals:

* `QUIT` - Wait for child to finish processing then exit
* `TERM` - Immediately kill child then exit
* `USR1` - Immediately kill child but don't exit

If you want to gracefully shutdown a Resque worker, use `QUIT`.

If you want to kill a stale or stuck child, use `USR1`. Processing
will continue as normal.

If you want to kill a stale or stuck child and shutdown, use `TERM`


Resque vs DelayedJob
--------------------

How does Resque compare to DelayedJob, and why would you choose one
over the other?

* Resque supports multiple queues
* DelayedJob supports finer grained priorities
* Resque workers are resilient to memory leaks / bloat
* DelayedJob workers are extremely simple and easy to modify
* Resque requires Redis
* DelayedJob requires ActiveRecord
* Resque can only place JSONable Ruby objects on a queue as arguments
* DelayedJob can place _any_ Ruby object on its queue as arguments
* Resque includes a Sinatra app for monitoring what's going on
* DelayedJob can be queryed from within your Rails app if you want to
  add an interface

If you're doing Rails development, you already have a database and
ActiveRecord. DelayedJob is super easy to setup and works great.
GitHub used it for many months to process almost 200 million jobs.

Choose Resque if:

* You need multiple queues
* You don't care / dislike numeric priorities
* You don't need to persist any Ruby object ever
* You have potentially huge queues
* You want to see what's going on
* You expect a lot of failure / chaos
* You can setup Redis

Choose DelayedJob if:

* You like numeric priorities
* You're not doing a gigantic amount of jobs each day
* Your queue stays small and nimble
* There is not a lot failure / chaos
* You want to easily throw anything on the queue
* You don't want to setup Redis

In no way is Resque a "better" DelayedJob, so make sure you pick the
tool that's best for your app.

Development
-----------


