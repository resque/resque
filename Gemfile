source "https://rubygems.org"
gemspec

case redis_version = ENV.fetch('REDIS_VERSION', 'latest')
when 'latest'
  gem 'redis', '~> 5.0'
else
  gem 'redis', "~> #{redis_version}.0"
end

gem "json"
gem "minitest", "~> 5.11"
gem "mocha", "~> 1.11", require: false
gem "rack-test", "~> 2.0"
gem "rake"
gem "rubocop", "~> 1.36"
gem "pry"
