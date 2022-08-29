$LOAD_PATH.unshift 'lib'
require 'resque/version'

Gem::Specification.new do |s|
  s.name              = "resque"
  s.version           = Resque::VERSION
  s.summary           = "Resque is a Redis-backed queueing system."
  s.homepage          = "https://github.com/resque/resque"
  s.email             = "steve@steveklabnik.com"
  s.authors           = [ "Chris Wanstrath", "Steve Klabnik", "Terence Lee", "Michael Bianco" ]

  s.files             = %w( README.markdown Rakefile LICENSE HISTORY.md )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.files            += Dir.glob("man/**/*")
  s.files            += Dir.glob("tasks/**/*")
  s.executables       = [ "resque", "resque-web" ]
  s.license           = 'MIT'

  s.extra_rdoc_files  = [ "LICENSE", "README.markdown" ]
  s.rdoc_options      = ["--charset=UTF-8"]

  s.required_ruby_version = ">= 2.3.0"

  s.add_dependency "redis-namespace", "~> 1.6"
  s.add_dependency "redis", ">= 4", "<5"
  s.add_dependency "sinatra", ">= 0.9.2"
  s.add_dependency "multi_json", "~> 1.0"
  s.add_dependency "mono_logger", "~> 1.0"

  s.description = <<description
    Resque is a Redis-backed Ruby library for creating background jobs,
    placing those jobs on multiple queues, and processing them later.

    Background jobs can be any Ruby class or module that responds to
    perform. Your existing classes can easily be converted to background
    jobs or you can create new classes specifically to do work. Or, you
    can do both.

    Resque is heavily inspired by DelayedJob (which rocks) and is
    comprised of three parts:

    * A Ruby library for creating, querying, and processing jobs
    * A Rake task for starting a worker which processes jobs
    * A Sinatra app for monitoring queues, jobs, and workers.
description

  s.add_development_dependency "thin"
  s.add_development_dependency "webrick"

  s.metadata['changelog_uri'] = 'https://github.com/resque/resque/blob/master/HISTORY.md'
  s.metadata['rubygems_mfa_required'] = 'true'
end
