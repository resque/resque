Resque Demo
-----------

This is a dirt simple Resque setup for you to play with.


### Starting the Demo App

Here's how to run the Sinatra app:

    $ git clone git://github.com/defunkt/resque.git
    $ cd resque/examples/demo
    $ rackup config.ru
    $ open http://localhost:9292/

Click 'Create New Job' a few times. You should see the number of
pending jobs rising.
  

### Starting the Demo Worker

Now in another shell terminal start the worker:

    $ cd resque/examples/demo
    $ VERBOSE=true QUEUE=default rake resque:work

You should see the following output:

    *** Starting worker hostname:90185:default
    *** got: (Job{default} | Demo::Job | [{}])
    Processed a job!
    *** done: (Job{default} | Demo::Job | [{}])

You can also use `VVERBOSE` (very verbose) if you want to see more:

    $ VERBOSE=true QUEUE=default rake resque:work
    *** Starting worker hostname:90399:default
    ** [05:55:09 2009-09-16] 90399: Registered signals
    ** [05:55:09 2009-09-16] 90399: Checking default
    ** [05:55:09 2009-09-16] 90399: Found job on default
    ** [05:55:09 2009-09-16] 90399: got: (Job{default} | Demo::Job | [{}])
    ** [05:55:09 2009-09-16] 90399: resque: Forked 90401 at 1253141709
    ** [05:55:09 2009-09-16] 90401: resque: Processing default since 1253141709
    Processed a job!
    ** [05:55:10 2009-09-16] 90401: done: (Job{default} | Demo::Job | [{}])

Notice that our workers `require 'job'` in our `Rakefile`. This
ensures they have our app loaded and can access the job classes.


### Starting the Resque frontend

Great, now let's check out the Resque frontend. Either click on 'View
Resque' in your web browser or run:

    $ open http://localhost:9292/resque/

You should see the Resque web frontend. 404 page? Don't forget the
trailing slash!


### config.ru

The `config.ru` shows you how to mount multiple Rack apps. Resque
should work fine on a subpath - feel free to load it up in your
Passenger app and protect it with some basic auth.


### That's it!

Click around, add some more queues, add more jobs, do whatever, have fun.
