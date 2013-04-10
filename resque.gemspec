$LOAD_PATH.unshift 'lib'
require 'resque/version'

Gem::Specification.new do |s|
  s.name              = "resque"
  s.version           = Resque::Version
  s.summary           = "Resque is a Redis-backed queueing system."
  s.homepage          = "https://github.com/defunkt/resque"
  s.email             = ["steve@steveklabnik.com", "hone02@gmail.com","chris@ozmm.org"]
  s.authors           = ["Steve Klabnik", "Terence Lee", "Chris Wanstrath"]

  s.files         = `git ls-files`.split($/).reject{ |f| f =~ /^examples/ }
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.extra_rdoc_files  = [ "LICENSE.txt", "CHANGELOG.md", "README.md", "CONTRIBUTING.md" ]
  s.rdoc_options      = ["--charset=UTF-8"]

  s.add_dependency "thor",            "~> 0.17"
  s.add_dependency "redis-namespace", "~> 1.0"
  s.add_dependency "json"
  s.add_dependency "mono_logger", "~> 1.0"
  s.add_dependency "activesupport", "~> 3.0.0"

  s.add_development_dependency "mock_redis", " ~> 0.7.0"

  s.description = %s{
    Resque is a Redis-backed Ruby library for creating background jobs,
    placing those jobs on multiple queues, and processing them later.}
end
