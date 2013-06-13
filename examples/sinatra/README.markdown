Resque Demo
-----------

This is a dirt simple Resque setup for you to play with.


### Starting the Demo App

Here's how to run the Sinatra app:

    $ git clone git://github.com/resque/resque.git
    $ cd resque/examples/sinatra
    $ ruby app.rb
    $ open http://localhost:9292/

Click 'Create New Job' a few times. You should see the number of
pending jobs rising.

### Starting the Demo Worker

Now in another shell terminal start the worker:

    $ cd resque/examples/sinatra
    $ bundle install
    $ bundle exec resque work -q default,failing -r ./job.rb

You should see the following output:

    *** Starting worker hostname:90185:default
    *** got: (Job{default} | Demo::Job | [{}])
    Processed a job!
    *** done: (Job{default} | Demo::Job | [{}])

You can also use `-vverbose` (`-vv`) (very verbose) if you want to see more:

    $ bundle exec resque work -q default,failing -r ./job -vv
    *** Starting worker hostname:90399:default
    ** [05:55:09 2009-09-16] 90399: Registered signals
    ** [05:55:09 2009-09-16] 90399: Checking default
    ** [05:55:09 2009-09-16] 90399: Found job on default
    ** [05:55:09 2009-09-16] 90399: got: (Job{default} | Demo::Job | [{}])
    ** [05:55:09 2009-09-16] 90399: resque: Forked 90401 at 1253141709
    ** [05:55:09 2009-09-16] 90401: resque: Processing default since 1253141709
    Processed a job!
    ** [05:55:10 2009-09-16] 90401: done: (Job{default} | Demo::Job | [{}])

Notice that you need to pass path to `job.rb` file in `-r` (`--require`) option. This
ensures that workers can access the job classes.

### That's it!

Click around, add some more queues, add more jobs, do whatever, have fun.
