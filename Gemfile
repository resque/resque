source "https://rubygems.org"
gemspec

case redis_version = ENV.fetch('REDIS_VERSION', 'latest')
when 'latest'
  gem 'redis', '~> 5.0'
else
  gem 'redis', "~> #{redis_version}.0"
end

rack_version = ENV.fetch('RACK_VERSION', '3')
gem "rack", "~> #{rack_version}.0"

if rack_version.to_i >= 3
  gem "rackup"
end

gem "benchmark"
gem "json"
gem "minitest", "~> 5.11"
gem "mocha", "~> 2.0", require: false
gem "ostruct"
gem "pry"
gem "rack-test", "~> 2.0"
gem "rake"
gem "rubocop", "~> 0.80"
