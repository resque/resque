Little Stuff
-----------

[ ] Show stale workers in red with a warning icon in the Sinatra app
[ ] GetException Failure support


Big Stuff
---------

### async

I want the `async` helper to be first class. Something like this:

    class Repository < ActiveRecord::Base
        include Resque::AsyncHelper
    end

This adds an `async` instance method and a `perform` class method.

The `async` method looks like this:

    def async(method, *args)
      Resque.enqueue(self.class, id, method, *args)
    end

The `perform` method looks like this:

    def self.perform(id, method, *args)
      find(id).send(method, *args)
    end

Of course, you can define your own `self.perform` and have it still 
work beautifully. We might override ours in GitHub to look like this:

    def self.perform(id, method, *args)
      return unless repo = cached_by_id(id)
      repo.send(method, *args)
    end

Then: `@repo.async(:update_disk_usage)` issues a job equivalent to:

    Resque.enqueue(Repository, 44, :update_disk_usage)

Booyah.


### gem install

`gem install resque` should pull in yajl, redis, sinatra, rake, and rack


### resque

`resque -c config.rb queue,list` should start a worker using the config.rb file.

Do it like Unicorn does it.


### Parent / Child => Master / Workers

On an ideal setup (REE + Linux) you'll have 2N Resque processes
running at any time: N parents and N children.

We can cut this number down to N+1 by moving from a parent / child
architecture to a master / workers architecture.

