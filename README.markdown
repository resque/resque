Resque
======

[![Gem Version](https://badge.fury.io/rb/resque.svg)](https://rubygems.org/gems/resque)
[![Build Status](https://github.com/resque/resque/actions/workflows/ci.yml/badge.svg)](https://github.com/resque/resque/actions/workflows/ci.yml)

Introduction
------------

Resque (pronounced like "rescue") is a Redis-backed library for creating
background jobs, placing those jobs on multiple queues, and processing
them later.

For the backstory, philosophy, and history of Resque's beginnings, please see [the blog post](http://github.com/blog/542-introducing-resque) (2009).

Background jobs can be any Ruby class or module that responds to
`perform`. Your existing classes can easily be converted to background
jobs or you can create new classes specifically to do work. Or, you
can do both.

Resque is heavily inspired by DelayedJob (which rocks) and comprises
three parts:

1. A Ruby library for creating, querying, and processing jobs
2. A Rake task for starting a worker which processes jobs
3. A Sinatra app for monitoring queues, jobs, and workers.

Resque workers can be  given multiple queues (a "queue list"),
distributed between multiple machines,
run anywhere with network access to the Redis server,
support priorities, are resilient to memory bloat / "leaks,"
tell you what they're doing, and expect failure.

Resque queues are persistent; support constant time, atomic push and
pop (thanks to Redis); provide visibility into their contents; and
store jobs as simple JSON packages.

The Resque frontend tells you what workers are doing, what workers are
not doing, what queues you're using, what's in those queues, provides
general usage stats, and helps you track failures.

Resque now supports Ruby 2.3.0 and above.
We will also only be supporting Redis 3.0 and above going forward.

### Note on the future of Resque

Would you like to be involved in Resque? Do you have thoughts about what
Resque should be and do going forward? There's currently an [open discussion here](https://github.com/resque/resque/issues/1759)
on just that topic, so please feel free to join in. We'd love to hear your thoughts
and/or have people volunteer to be a part of the project!

Example
-------

Resque jobs are Ruby classes (or modules) which respond to the
`perform` method. Here's an example:


``` ruby
class Archive
  @queue = :file_serve

  def self.perform(repo_id, branch = 'master')
    repo = Repository.find(repo_id)
    repo.create_archive(branch)
  end
end
```

The `@queue` class instance variable determines which queue `Archive`
jobs will be placed in. Queues are arbitrary and created on the fly -
you can name them whatever you want and have as many as you want.

To place an `Archive` job on the `file_serve` queue, we might add this
to our application's pre-existing `Repository` class:

``` ruby
class Repository
  def async_create_archive(branch)
    Resque.enqueue(Archive, self.id, branch)
  end
end
```

Now when we call `repo.async_create_archive('masterbrew')` in our
application, a job will be created and placed on the `file_serve`
queue.

Later, a worker will run something like this code to process the job:

``` ruby
klass, args = Resque.reserve(:file_serve)
klass.perform(*args) if klass.respond_to? :perform
```

Which translates to:

``` ruby
Archive.perform(44, 'masterbrew')
```

Let's start a worker to run `file_serve` jobs:

    $ cd app_root
    $ QUEUE=file_serve rake resque:work

This starts one Resque worker and tells it to work off the
`file_serve` queue. As soon as it's ready it'll try to run the
`Resque.reserve` code snippet above and process jobs until it can't
find any more, at which point it will sleep for a small period and
repeatedly poll the queue for more jobs.

Installation
------------

Add the gem to your Gemfile:

    gem 'resque'

Next, install it with Bundler:

    $ bundle

#### Rack

In your Rakefile, or some other file in `lib/tasks` (ex: `lib/tasks/resque.rake`), load the resque rake tasks:

``` ruby
require 'resque'
require 'resque/tasks'
require 'your/app' # Include this line if you want your workers to have access to your application
```

#### Rails

To make resque specific changes, you can override the `resque:setup` job in `lib/tasks` (ex: `lib/tasks/resque.rake`). GitHub's setup task looks like this:

``` ruby
task "resque:setup" => :environment do
  Grit::Git.git_timeout = 10.minutes
end
```

We don't want the `git_timeout` as high as 10 minutes in our web app,
but in the Resque workers it's fine.

Running Workers
---------------

Resque workers are rake tasks that run forever. They basically do this:

``` ruby
start
loop do
  if job = reserve
    job.process
  else
    sleep 5 # Polling frequency = 5
  end
end
shutdown
```

Starting a worker is simple:

    $ QUEUE=* rake resque:work

Or, you can start multiple workers:

    $ COUNT=2 QUEUE=* rake resque:workers

This will spawn two Resque workers, each in its own process. Hitting
ctrl-c should be sufficient to stop them all.

#### Priorities and Queue Lists

Resque doesn't support numeric priorities but instead uses the order
of queues you give it. We call this list of queues the "queue list."

Let's say we add a `warm_cache` queue in addition to our `file_serve`
queue. We'd now start a worker like so:

    $ QUEUES=file_serve,warm_cache rake resque:work

When the worker looks for new jobs, it will first check
`file_serve`. If it finds a job, it'll process it then check
`file_serve` again. It will keep checking `file_serve` until no more
jobs are available. At that point, it will check `warm_cache`. If it
finds a job it'll process it then check `file_serve` (repeating the
whole process).

In this way you can prioritize certain queues. At GitHub we start our
workers with something like this:

    $ QUEUES=critical,archive,high,low rake resque:work

Notice the `archive` queue - it is specialized and in our future
architecture will only be run from a single machine.

At that point we'll start workers on our generalized background
machines with this command:

    $ QUEUES=critical,high,low rake resque:work

And workers on our specialized archive machine with this command:

    $ QUEUE=archive rake resque:work

#### Running All Queues

If you want your workers to work off of every queue, including new
queues created on the fly, you can use a splat:

    $ QUEUE=* rake resque:work

Queues will be processed in alphabetical order.

Or, prioritize some queues above `*`:

    # QUEUE=critical,* rake resque:work

#### Running All Queues Except for Some

If you want your workers to work off of all queues except for some,
you can use negation:

    $ QUEUE=*,!low rake resque:work

Negated globs also work. The following will instruct workers to work
off of all queues except those beginning with `file_`:

    $ QUEUE=*,!file_* rake resque:work

Note that the order in which negated queues are specified does not
matter, so `QUEUE=*,!file_*` and `QUEUE=!file_*,*` will have the same
effect.

#### Process IDs (PIDs)

There are scenarios where it's helpful to record the PID of a resque
worker process.  Use the PIDFILE option for easy access to the PID:

    $ PIDFILE=./resque.pid QUEUE=file_serve rake resque:work

#### Running in the background

There are scenarios where it's helpful for
the resque worker to run itself in the background (usually in combination with
PIDFILE).  Use the BACKGROUND option so that rake will return as soon as the
worker is started.

    $ PIDFILE=./resque.pid BACKGROUND=yes QUEUE=file_serve rake resque:work

#### Polling frequency

You can pass an INTERVAL option which is a float representing the polling frequency.
The default is 5 seconds, but for a semi-active app you may want to use a smaller value.

    $ INTERVAL=0.1 QUEUE=file_serve rake resque:work

The Front End
-------------

Resque comes with a Sinatra-based front end for seeing what's up with
your queue.

![The Front End](https://camo.githubusercontent.com/64d150a243987ffbc33f588bd6d7722a0bb8d69a/687474703a2f2f7475746f7269616c732e6a756d7073746172746c61622e636f6d2f696d616765732f7265737175655f6f766572766965772e706e67)

#### Standalone

If you've installed Resque as a gem running the front end standalone is easy:

    $ resque-web

It's a thin layer around `rackup` so it's configurable as well:

    $ resque-web -p 8282

If you have a Resque config file you want evaluated just pass it to
the script as the final argument:

    $ resque-web -p 8282 rails_root/config/initializers/resque.rb

You can also set the namespace directly using `resque-web`:

    $ resque-web -p 8282 -N myapp

or set the Redis connection string if you need to do something like select a different database:

    $ resque-web -p 8282 -r localhost:6379:2

#### Passenger

Using Passenger? Resque ships with a `config.ru` you can use. See
Phusion's guide:

Apache: <https://www.phusionpassenger.com/library/deploy/apache/deploy/ruby/>
Nginx: <https://www.phusionpassenger.com/library/deploy/nginx/deploy/ruby/>

#### Rack::URLMap

If you want to load Resque on a subpath, possibly alongside other
apps, it's easy to do with Rack's `URLMap`:

``` ruby
require 'resque/server'

run Rack::URLMap.new \
  "/"       => Your::App.new,
  "/resque" => Resque::Server.new
```

Check `examples/demo/config.ru` for a functional example (including
HTTP basic auth).

#### Rails

You can also mount Resque on a subpath in your existing Rails app by adding `require 'resque/server'` to the top of your routes file or in an initializer then adding this to `routes.rb`:

``` ruby
mount Resque::Server.new, :at => "/resque"
```

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

#### Persistence

Jobs are persisted to queues as JSON objects. Let's take our `Archive`
example from above. We'll run the following code to create a job:

``` ruby
repo = Repository.find(44)
repo.async_create_archive('masterbrew')
```

The following JSON will be stored in the `file_serve` queue:

``` javascript
{
    'class': 'Archive',
    'args': [ 44, 'masterbrew' ]
}
```

Because of this your jobs must only accept arguments that can be JSON encoded.

So instead of doing this:

``` ruby
Resque.enqueue(Archive, self, branch)
```

do this:

``` ruby
Resque.enqueue(Archive, self.id, branch)
```

This is why our above example (and all the examples in `examples/`)
uses object IDs instead of passing around the objects.

While this is less convenient than just sticking a marshaled object
in the database, it gives you a slight advantage: your jobs will be
run against the most recent version of an object because they need to
pull from the DB or cache.

If your jobs were run against marshaled objects, they could
potentially be operating on a stale record with out-of-date information.


#### send_later / async

Want something like DelayedJob's `send_later` or the ability to use
instance methods instead of just methods for jobs? See the `examples/`
directory for goodies.

We plan to provide first class `async` support in a future release.


#### Failure

If a job raises an exception, it is logged and handed off to the
`Resque::Failure` module. Failures are logged either locally in Redis
or using some different backend. To see exceptions while developing,
see details below under Logging.

For example, Resque ships with Airbrake support. To configure it, put
the following into an initialisation file or into your rake job:

``` ruby
# send errors which occur in background jobs to redis and airbrake
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'resque/failure/airbrake'

Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::Airbrake]
Resque::Failure.backend = Resque::Failure::Multiple
```

Keep this in mind when writing your jobs: you may want to throw
exceptions you would not normally throw in order to assist debugging.


#### Rails example

If you are using ActiveJob here's how your job definition will look:

``` ruby
class ArchiveJob < ApplicationJob
  queue_as :file_serve

  def perform(repo_id, branch = 'master')
    repo = Repository.find(repo_id)
    repo.create_archive(branch)
  end
end
```

``` ruby
class Repository
  def async_create_archive(branch)
    ArchiveJob.perform_later(self.id, branch)
  end
end
```

It is important to run `ArchiveJob.perform_later(self.id, branch)` rather than `Resque.enqueue(Archive, self.id, branch)`.
Otherwise Resque will process the job without actually doing anything.
Even if you put an obviously buggy line like `0/0` in the `perform` method,
the job will still succeed.


Configuration
-------------

#### Redis

You may want to change the Redis host and port Resque connects to, or
set various other options at startup.

Resque has a `redis` setter which can be given a string or a Redis
object. This means if you're already using Redis in your app, Resque
can re-use the existing connection.

String: `Resque.redis = 'localhost:6379'`

Redis: `Resque.redis = $redis`

For our rails app we have a `config/initializers/resque.rb` file where
we load `config/resque.yml` by hand and set the Redis information
appropriately.

Here's our `config/resque.yml`:

    development: localhost:6379
    test: localhost:6379
    staging: redis1.se.github.com:6379
    fi: localhost:6379
    production: <%= ENV['REDIS_URL'] %>

And our initializer:

``` ruby
rails_root = ENV['RAILS_ROOT'] || File.dirname(__FILE__) + '/../..'
rails_env = ENV['RAILS_ENV'] || 'development'
config_file = rails_root + '/config/resque.yml'

resque_config = YAML::load(ERB.new(IO.read(config_file)).result)
Resque.redis = resque_config[rails_env]
```

Easy peasy! Why not just use `RAILS_ROOT` and `RAILS_ENV`? Because
this way we can tell our Sinatra app about the config file:

    $ RAILS_ENV=production resque-web rails_root/config/initializers/resque.rb

Now everyone is on the same page.

Also, you could disable jobs queueing by setting 'inline' attribute.
For example, if you want to run all jobs in the same process for cucumber, try:

``` ruby
Resque.inline = ENV['RAILS_ENV'] == "cucumber"
```

#### Logging

Workers support basic logging to STDOUT.

You can control the logging threshold using `Resque.logger.level`:

```ruby
# config/initializers/resque.rb
Resque.logger.level = Logger::DEBUG
```

If you want Resque to log to a file, in Rails do:

```ruby
# config/initializers/resque.rb
Resque.logger = Logger.new(Rails.root.join('log', "#{Rails.env}_resque.log"))
```

#### Namespaces

If you're running multiple, separate instances of Resque you may want
to namespace the keyspaces so they do not overlap. This is not unlike
the approach taken by many memcached clients.

This feature is provided by the [redis-namespace](http://github.com/resque/redis-namespace) library, which
Resque uses by default to separate the keys it manages from other keys
in your Redis server.

Simply use the `Resque.redis.namespace` accessor:

``` ruby
Resque.redis.namespace = "resque:GitHub"
```

We recommend sticking this in your initializer somewhere after Redis
is configured.

#### Storing Statistics
 Resque allows to store count of processed and failed jobs.

 By default it will store it in Redis using the keys `stats:processed` and `stats:failed`.

 Some apps would want another stats store, or even a null store:

 ```ruby
# config/initializers/resque.rb
class NullDataStore
  def stat(stat)
    0
  end

  def increment_stat(stat, by)
  end

  def decrement_stat(stat, by)
  end

  def clear_stat(stat)
  end
end

Resque.stat_data_store = NullDataStore.new
```

Plugins and Hooks
-----------------

For a list of available plugins see
<https://github.com/resque/resque/wiki/plugins>.

If you'd like to write your own plugin, or want to customize Resque
using hooks (such as `Resque.after_fork`), see
[docs/HOOKS.md](http://github.com/resque/resque/blob/master/docs/HOOKS.md).


Additional Information
----------------------

#### Resque vs DelayedJob

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
* DelayedJob can be queried from within your Rails app if you want to
  add an interface

If you're doing Rails development, you already have a database and
ActiveRecord. DelayedJob is super easy to setup and works great.
GitHub used it for many months to process almost 200 million jobs.

Choose Resque if:

* You need multiple queues
* You don't care / dislike numeric priorities
* You don't need to persist every Ruby object ever
* You have potentially huge queues
* You want to see what's going on
* You expect a lot of failure / chaos
* You can setup Redis
* You're not running short on RAM

Choose DelayedJob if:

* You like numeric priorities
* You're not doing a gigantic amount of jobs each day
* Your queue stays small and nimble
* There is not a lot failure / chaos
* You want to easily throw anything on the queue
* You don't want to setup Redis

In no way is Resque a "better" DelayedJob, so make sure you pick the
tool that's best for your app.

#### Forking

On certain platforms, when a Resque worker reserves a job it
immediately forks a child process. The child processes the job then
exits. When the child has exited successfully, the worker reserves
another job and repeats the process.

Why?

Because Resque assumes chaos.

Resque assumes your background workers will lock up, run too long, or
have unwanted memory growth.

If Resque workers processed jobs themselves, it'd be hard to whip them
into shape. Let's say one is using too much memory: you send it a
signal that says "shutdown after you finish processing the current
job," and it does so. It then starts up again - loading your entire
application environment. This adds useless CPU cycles and causes a
delay in queue processing.

Plus, what if it's using too much memory and has stopped responding to
signals?

Thanks to Resque's parent / child architecture, jobs that use too much memory
release that memory upon completion. No unwanted growth.

And what if a job is running too long? You'd need to `kill -9` it then
start the worker again. With Resque's parent / child architecture you
can tell the parent to forcefully kill the child then immediately
start processing more jobs. No startup delay or wasted cycles.

The parent / child architecture helps us keep tabs on what workers are
doing, too. By eliminating the need to `kill -9` workers we can have
parents remove themselves from the global listing of workers. If we
just ruthlessly killed workers, we'd need a separate watchdog process
to add and remove them to the global listing - which becomes
complicated.

Workers instead handle their own state.

#### `at_exit` Callbacks

Resque uses `Kernel#exit!` for exiting its workers' child processes. So any `at_exit` callback defined in your application won't be executed when the job is finished and the child process exits.

You can alter this behavior by setting the `RUN_AT_EXIT_HOOKS` environment variable.

#### Parents and Children

Here's a parent / child pair doing some work:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Forked 92102 at 1253142769
    92102 resque: Processing file_serve since 1253142769

You can clearly see that process 92099 forked 92102, which has been
working since 1253142769.

(By advertising the time they began processing you can easily use monit
or god to kill stale workers.)

When a parent process is idle, it lets you know what queues it is
waiting for work on:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Waiting for file_serve,warm_cache


#### Signals

Resque workers respond to a few different signals:

* `QUIT` - Wait for child to finish processing then exit
* `TERM` / `INT` - Immediately kill child then exit
* `USR1` - Immediately kill child but don't exit
* `USR2` - Don't start to process any new jobs
* `CONT` - Start to process new jobs again after a USR2

If you want to gracefully shutdown a Resque worker, use `QUIT`.

If you want to kill a stale or stuck child, use `USR1`. Processing
will continue as normal unless the child was not found. In that case
Resque assumes the parent process is in a bad state and shuts down.

If you want to kill a stale or stuck child and shutdown, use `TERM`

If you want to stop processing jobs, but want to leave the worker running
(for example, to temporarily alleviate load), use `USR2` to stop processing,
then `CONT` to start it again. It's also possible to [pause all workers](#pausing-all-workers).

#### Heroku

When shutting down processes, Heroku sends every process a TERM signal at the
same time. By default this causes an immediate shutdown of any running job
leading to frequent `Resque::TermException` errors.  For short running jobs, a simple
solution is to give a small amount of time for the job to finish
before killing it.

Resque doesn't handle this out of the box (for both cedar-14 and heroku-16), you need to
install the [`resque-heroku-signals`](https://github.com/iloveitaly/resque-heroku-signals)
addon which adds the required signal handling to make the behavior described above work.
Related issue: https://github.com/resque/resque/issues/1559

To accomplish this set the following environment variables:

* `RESQUE_PRE_SHUTDOWN_TIMEOUT` - The time between the parent receiving a shutdown signal (TERM by default) and it sending that signal on to the child process. Designed to give the child process
time to complete before being forced to die.

* `TERM_CHILD` - Must be set for `RESQUE_PRE_SHUTDOWN_TIMEOUT` to be used. After the timeout, if the child is still running it will raise a `Resque::TermException` and exit.

* `RESQUE_TERM_TIMEOUT` - By default you have a few seconds to handle `Resque::TermException` in your job. `RESQUE_TERM_TIMEOUT` and `RESQUE_PRE_SHUTDOWN_TIMEOUT` must be lower than the [heroku dyno timeout](https://devcenter.heroku.com/articles/limits#exit-timeout).

#### Pausing all workers

Workers will not process pending jobs if the Redis key `pause-all-workers` is set with the string value "true".

``` ruby
Resque.redis.set('pause-all-workers', 'true')
```

Nothing happens to jobs that are already being processed by workers.

Unpause by removing the Redis key `pause-all-workers`.

``` ruby
Resque.redis.del('pause-all-workers')
```

#### Monitoring

##### god

If you're using god to monitor Resque, we have provided example
configs in `examples/god/`. One is for starting / stopping workers,
the other is for killing workers that have been running too long.

##### monit

If you're using monit, `examples/monit/resque.monit` is provided free
of charge. This is **not** used by GitHub in production, so please
send patches for any tweaks or improvements you can make to it.

#### Mysql::Error: MySQL server has gone away

If your workers remain idle for too long they may lose their MySQL connection. Depending on your version of Rails, we recommend the following:

##### Rails
In your `perform` method, add the following line:

``` ruby
class MyTask
  def self.perform
    ActiveRecord::Base.verify_active_connections!
    # rest of your code
  end
end
```

The Rails doc says the following about `verify_active_connections!`:

    Verify active connections and remove and disconnect connections associated with stale threads.

##### Rails 4.x

In your `perform` method, instead of `verify_active_connections!`, use:

``` ruby
class MyTask
  def self.perform
    ActiveRecord::Base.clear_active_connections!
    # rest of your code
  end
end
```

From the Rails docs on [`clear_active_connections!`](http://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/ConnectionHandler.html#method-i-clear_active_connections-21):

    Returns any connections in use by the current thread back to the pool, and also returns connections to the pool cached by threads that are no longer alive.

Development
-----------

Want to hack on Resque?

First clone the repo and run the tests:

    git clone git://github.com/resque/resque.git
    cd resque
    rake test

If the tests do not pass make sure you have Redis installed
correctly (though we make an effort to tell you if we feel this is the
case). The tests attempt to start an isolated instance of Redis to
run against.

Also make sure you've installed all the dependencies correctly. For
example, try loading the `redis-namespace` gem after you've installed
it:

    $ irb
    >> require 'rubygems'
    => true
    >> require 'redis/namespace'
    => true

If you get an error requiring any of the dependencies, you may have
failed to install them or be seeing load path issues.

#### Demo
Resque ships with a demo Sinatra app for creating jobs that are later
processed in the background.

Try it out by looking at the README, found at `examples/demo/README.markdown`.

#### Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

Once you've made your great commits:

1. [Fork](http://help.github.com/forking/) Resque
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create a [Pull Request](http://help.github.com/pull-requests/) from your branch

Questions
---------

Please add them to the [FAQ](https://github.com/resque/resque/wiki/FAQ) or open an issue on this repo.

Meta
----

* Code: `git clone git://github.com/resque/resque.git`
* Home: <http://github.com/resque/resque>
* Docs: <http://rubydoc.info/gems/resque>
* Bugs: <http://github.com/resque/resque/issues>
* Gems: <https://rubygems.org/gems/resque>

This project uses [Semantic Versioning](http://semver.org/)

Author
------

Chris Wanstrath :: chris@ozmm.org :: @defunkt
