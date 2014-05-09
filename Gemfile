source "https://rubygems.org"

gemspec
gem "redis-namespace", :git => "https://github.com/resque/redis-namespace.git"

group :development do
  gem 'rake'
end

group :documentation do
  gem 'rdoc'
  gem 'yard-thor', '~>0.2', :github => 'lsegal/yard-thor'
  gem 'kramdown'
  gem 'coveralls', :require => false
end

group :development, :documentation do
  gem 'yard'
end

group :test do
  gem "json"
  gem "minitest", '4.7.0'
  gem "minitest-stub-const"
  gem 'mock_redis', '~> 0.13.2'
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
  gem 'rubysl-stringio'
  gem 'rubysl-test-unit'
  gem 'rubysl-mutex_m'
  gem 'rubysl-irb'
end
