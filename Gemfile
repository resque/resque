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
gem "mocha", "~> 2.0", require: false

ruby_version = Gem::Version.new(RUBY_VERSION)
if ruby_version >= Gem::Version.new("2.4") && ruby_version < Gem::Version.new("2.6")
  gem "rack", "~> 1"
elsif ruby_version >= Gem::Version.new("2.6") && ruby_version < Gem::Version.new("2.7")
  gem "rack", "~> 2"
else
  gem "rack"
end

gem "rack-test", "~> 2.0"
gem "rake"
gem "rubocop", "~> 0.80"
gem "pry"
