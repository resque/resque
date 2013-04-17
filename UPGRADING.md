Upgrading Resque
================

So you want to upgrade from Resque 1.x to 2.0? Here's everything that you need
to know.

  * Rake was replaced with Thor. Rake tasks are still supported and backward compatible, they're deprecated and will be removed in 2.1
    Resque provides `resque` bin file instead which you should use for running workers and other Resque-related stuff.

    Old `$ QUEUE=high,failure rake resque:work` translates to `$ resque work -q high,failure`. Check all available tasks by running `resque help`

  * Resque::Workers#initialize now takes a client as an option. This manages
    its connection to Redis.
