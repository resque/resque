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

1. A Ruby library for creating jobs
2. A Rake task for processing jobs
3. A Sinatra app for monitoring queues, jobs, and workers.

Resque workers can be distributed between multiple machines,
support priorities, are resililent to memory bloat / "leaks," are
optimized for REE (but work on MRI and JRuby), tell you what they're
doing, and expect failure.

Resque queues are persistent, support atomic, constant time push and
pop (thanks to Redis), provide visibility into their contents, and
store jobs as simple JSON packages.

The Resque frontend tells you what workers are doing, what workers are
not doing, what queues you're using, what's in those queues, provides
general usage stats, and helps you track failures.

Resque is currently used to process millions of jobs each week by
GitHub.

The Blog Post
-------------

For the backstory, philosophy, and history of Resque's beginnings,
please see [the blog post][0].

Overview
--------

Resque allows you to create jobs and place them on a queue, then,
later, pull those jobs off the queue and process them.

Resque supports multiple, arbitrary queues which can be created on the
fly. 

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

Queues
------

Workers
-------

### Signals

* `QUIT` - Wait for child to finish processing then exit
* `TERM` - Immediately kill child then exit
* `USR1` - Immediately kill child, don't exit

Development
-----------


