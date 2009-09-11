Resque
======

Resque creates and processes background jobs. It is heavily inspired
by DelayedJob, which rocks.

Resque is comprised of three parts:

1. Queues: FIFO queues for storing jobs to be processed
2. Workers: Persistent, distributed Ruby processes which do work
3. Frontend: A Sinatra app for monitoring queues and workers

Resque workers can be distributed between multiple machines,
support priorities, are resililent to memory bloat / "leaks," are
optimized for REE (but work on MRI and JRuby), tell you what they're
doing, and expect failure.

Resque queues are persistent, support atomic push and pop, support
constant time push and pop, provide visibility into their contents,
and store plain-jane Ruby classes as jobs.

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

Here is a complete Resque job:

    class Archive
      @queue = :file_serve
      
      def self.perform(repo_id, branch = 'master')
        repo = Repository.find(repo_id)
        repo.create_archive(branch)
      end
    end

And here's some code that might live in our `Repository` class:

    class Repository
      def async_create_archive(branch)
        Resque.enqueue(Archive, self.id, branch)
      end
    end

Now when we call `repo.async_create_archive('masterbrew')` in our
application, a job will be created and placed on the `file_serve`
queue.

The job itself is a JSON encoded payload which will looks like:

    {
      'class' => 'Archive',
      'args' => [ 44, 'masterbrew' ]
    }

Later, a worker will essentially run this code to process the job:
  
    payload = Resque.reserve(:file_serve)
    
    # klass = Archive
    klass = payload['class'].to_class
    
    # Archive.perform(44, 'masterbrew')
    klass.perform(*payload['args'])

That's all there is to it. Your app uses Resque to push a small JSON
payload onto a list which a worker process pulls off the list and uses
to execute code.

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

Queues
------

Signals
-------

* `QUIT` - Wait for child to finish processing then exit
* `TERM` - Immediately kill child then exit
* `USR1` - Immediately kill child, don't exit
