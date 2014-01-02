source "https://rubygems.org"

gemspec
gem "redis-namespace", :git => "https://github.com/resque/redis-namespace.git"

group :development do
  gem 'rake'
  gem 'yard'
end

group :documentation do
  gem 'rdoc'
  gem 'yard'
  gem 'yard-thor', '~>0.2', :github => 'lsegal/yard-thor'
  gem 'kramdown'
  gem 'coveralls', :require => false
end

group :test do
  gem "rack-test", "~> 0.5"
  gem "json"
  gem "minitest", '4.7.0'
  gem "minitest-stub-const"
  gem "sinatra"
  gem 'mock_redis', :git => "https://github.com/causes/mock_redis.git"
end

platforms :rbx do
  # These are the ruby standard library
  # dependencies and transitive dependencies.
  gem 'rubysl-net-http'
  gem 'rubysl-socket'
  gem 'rubysl-logger'
  gem 'rubysl-cgi'
  gem 'rubysl-uri'
  gem 'rubysl-timeout'
  gem 'rubysl-zlib'
  gem 'rubysl-json'
  gem 'rubysl-stringio'
  gem 'rubysl-test-unit'
  gem 'rubysl-mutex_m'
  gem 'rubysl-irb'
end
