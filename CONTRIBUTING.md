Contributing to Resque
======================

First of all: thank you! We appreciate any help you can give Resque.

The main way to contribute to Resque is to write some code! Here's how:

1. [Fork][1] Resque
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create a [Pull Request](http://help.github.com/pull-requests/) from your
   branch
5. That's it!

If you're not doing some sort of refactoring, a CHANGELOG entry is appropriate.
Please include them in pull requests adding features or fixing bugs.

Oh, and 80 character columns, please!

Branches
--------

The `1-x-stable` branch is what is currently being released as `1.x.y`.

The `master` branch is what will become 2.0.

It's suggested that you make your pull request against the master branch by
default, and backport the fix with a second pull request where applicable.

Tests
-----

We use minitest for testing. If you're working against master, you'll find
a bunch of tests in `test/legacy`. These are the older Resque tests. Don't
look at them unless your code breaks them. Consider these black-box acceptance
tests. We don't like them, but we want to make sure we're not breaking
anything.

A simple `bundle exec rake` will run all the tests. Make sure they pass when
you submit a pull request.

Please include tests with your pull request.

Documentation
-------------

Writing docs is really important. We use yard to generate our documentation.
Please include docs in your pull requests.

Bugs & Feature Requests
-----------------------

You can file bugs on the [issues
tracker](https://github.com/resque/resque/issues), and tag them with 'bug'.
Feel free to ask for features there, too, if you'd like.

Help
----

If you have a question or want to discuss something, the Resque mailng list
might just be the place. [resque@librelist.com](mailto:resque@librelist.com)
is the address you want, send an email there and it'll take care of you.
