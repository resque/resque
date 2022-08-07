source "https://rubygems.org"
gemspec

case resque_version = ENV.fetch('REDIS_VERSION', 'latest')
when 'latest'
  gem 'redis', '~> 4.7'
else
  gem 'redis', resque_version
end

gem "json"
gem "minitest", "~> 5.11"
gem "mocha", "~> 1.11", require: false
gem "rack-test", "~> 2.0"
gem "rake"
gem "rubocop", "~> 0.80"
gem "pry"
