Resque
======

Resque (pronounced like "rescue") is a Redis-backed library for creating
background jobs, placing those jobs on multiple queues, and processing
them later.

  - [![Code Climate](https://img.shields.io/codeclimate/github/resque/resque.svg)](https://codeclimate.com/github/resque/resque)
  - [![Build Status](https://img.shields.io/travis/resque/resque/master.svg)](https://travis-ci.org/resque/resque)
  - [![Coverage Status](https://img.shields.io/coveralls/resque/resque/master.svg)](https://coveralls.io/r/resque/resque)
  - [![Inline docs](http://inch-ci.org/github/resque/resque.svg)](http://inch-ci.org/github/resque/resque)

### A note about branches

This branch is the master branch, which contains work towards Resque 2.0. If
you're currently using Resque, you'll want to check out [the 1-x-stable
branch](https://github.com/resque/resque/tree/1-x-stable), and particularly
[its README](https://github.com/resque/resque/blob/1-x-stable/README.markdown),
which is more accurate for the code you're running in production.

Also, this README is written first, so lots of things in here may not work the
exact way that they say they might here. Yay 2.0!

### Back to your regularly scheduled README.

You can't always do work right away. Sometimes, you need to do it later. Resque
is a really simple way to manage a pile of work that your application needs
to do: 1.5 million installs can't be wrong!

To define some work, make a job. Jobs need a `work` method:

```ruby
class ImageConversionJob
  def work
    # convert some kind of image here
  end
end
```

Next, we need to procrastinate! Let's put your job on the queue:

```ruby
resque = Resque.new
resque << ImageConversionJob.new
```

Neat! This unit of work will be stored in Redis. We can spin up a worker to
grab some work off of the queue and do the work:

```
bin/resque work
```

This process polls Redis, grabs any jobs that need to be done, and then does
them. :metal:

## Installation

To install Resque, add the gem to your Gemfile:

```ruby
gem "resque", "~> 2.0.0.pre.1", github: "resque/resque"
```

Then run `bundle`. If you're not using Bundler, just `gem install resque`.

### Requirements

Resque is used by a large number of people, across a diverse set of codebases.
There is no official requirement other than Ruby 1.9.3 or newer. We of course
recommend Ruby 2.0.0, but test against many Rubies, as you can see from our
[.travis.yml](https://github.com/resque/resque/blob/master/.travis.yml).

We would love to support non-MRI Rubies, but they may have bugs. We would love
some contributions to clear up failures on these Rubies, but they are set to
allow failure in our CI.

We officially support Rails 2.3.x and newer, though we recommend that you're on
Rails 3.2 or 4.

### Backwards Compatibility

Resque uses [SemVer](http://semver.org/), and takes it seriously. If you find
an interface regression, please [file an issue](https://github.com/resque/resque/issues)
so that we can address it.

If you have previously used Resque 1.23, the transition to 2.0 shouldn't be
too painful: we've tried to upgrade _interfaces_ but leave _semantics_ largely
in place. Check out
[UPGRADING.md](https://github.com/resque/resque/blob/master/UPGRADING.md) for
detailed examples of what needs to be done.

## Jobs

What deserves to be a background job? Anything that's not always super fast.
There are tons of stuff that an application does that falls under the 'not
always fast' category:

* Warming caches
* Counting disk usage
* Building tarballs
* Firing off web hooks
* Creating events in the db and pre-caching them
* Building graphs
* Deleting users

And it's not always web stuff, either. A command-line client application that
does web scraping and crawling is a great use of jobs, too.

### In Redis

Jobs are persisted in Redis via JSON serialization. Basically, the job looks
like this:

```json
{
    "class": "Email",
    "vars": {
      "to": "foo@example.com",
      "from": "steve@example.com"
    }
}
```

When Resque fetches this job from Redis, it will do something like this:

```ruby
json = fetch_json_from_redis

job = json["class"].constantize.new
json["vars"].each {|k, v| job.instance_variable_set("@#{k}", v) }
job.work
```

Ta da! Simple.

### Failure

When jobs fail, the failure is stored in Redis, too, so you can check them out
and possibly re-queue them.

## Workers

You can start up a worker with

```
$ bin/resque work
```

This will basically loop over and over, polling for jobs and doing the work.
You can have workers work on a specific queue with the `--queue` option:

```
$ bin/resque work --queues=high,low
$ bin/resque work --queue=high
```

This starts two workers working on the `high` queue, one of which also polls
the `low` queue.

You can control the length of the poll with `interval`:

```
$ bin/resque work --interval=1
```

Now workers will check for a new job every second. The default is 5.

Resque workers respond to a few different signals:

    QUIT - Wait for child to finish processing then exit
    TERM / INT - Immediately kill child then exit
    USR1 - Immediately kill child but don't exit
    USR2 - Don't start to process any new jobs
    CONT - Start to process new jobs again after a USR2

### Queue Priority

Queues are picked off in order of their priority. A job from a lower priority queue will only be
picked off if there are no jobs for a higher priority queue available.

See Resque::WorkerQueueList#search_order for more details.

## Configuration

You can configure Resque via a YAML `.resque` file in the root of your project:

```
queues: 'high,med,low'
require: 'some_context.rb'
pid_file: 'tmp/pids/resque.pid'
interval: 1
daemon: true
timeout: 5
graceful_term: false
```

Then pass the configuration to the resque CLI: `bin/resque work -c='./.resque'`.

You can also configure Resque via `Resque.configure`:

```ruby
Resque.configure do |config|

  # Set the redis connection. Takes any of:
  #   String - a redis url string (e.g., 'redis://host:port')
  #   String - 'hostname:port[:db][/namespace]'
  #   Redis - a redis connection that will be namespaced :resque
  #   Redis::Namespace - a namespaced redis connection that will be used as-is
  #   Redis::Distributed - a distributed redis connection that will be used as-is
  #   Hash - a redis connection hash (e.g. {:host => 'localhost', :port => 6379, :db => 0})
  config.redis = 'localhost:6379:alpha/high'

end
```

## Hooks and Plugins

Please see [HOOKS.md](https://github.com/resque/resque/blob/master/docs/HOOKS.md).

## Contributing

Please see [CONTRIBUTING.md](https://github.com/resque/resque/blob/master/CONTRIBUTING.md).

## Other Implementations

You can write your Resque workers in other languages, too:

* [Go](http://www.goworker.org/)
* [Java](https://github.com/gresrun/jesque)
* [CoffeeScript](https://github.com/technoweenie/coffee-resque)

## Anything we missed?

If there's anything at all that you need or want to know, please email either
[the mailing list](mailto:resque@librelist.com) or [Steve
Klabnik](mailto:steve@steveklabnik.com) and we'll get you sorted.
