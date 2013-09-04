# Basic Resque Example

This short program has two parts, a `my_job.rb` file which contains a module of a 'job' that can be executed in the background by a resque worker; and a `simple.rb` file which queues up this job for execution. 

To try it out, run the following:

* Install the required gems: `bundle install`
* If you haven't used Redis before, you'll have to install it. On OS X, it can be done with the Homebrew package manager: `brew install redis`
* And then in a new terminal tab run the redis server: `redis-server`
* You can realtime logs in Redis by running `redis-cli monitor` from another terminal tab.
* Run `simple.rb` to queue up the job: `ruby simple.rb`
* Start a worker to execute the jobs: `resque work -r ./my_job.rb`