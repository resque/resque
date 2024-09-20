#
# Setup
#

load 'lib/tasks/redis.rake'

$LOAD_PATH.unshift 'lib'
require 'resque/tasks'

def command?(command)
  system("type #{command} > /dev/null 2>&1")
end

require 'rubygems'
require 'bundler/setup'
require 'bundler/gem_tasks'


#
# Tests
#

require 'rake/testtask'

task :default => :test

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/*_test.rb'].exclude('test/active_job/**/*')
end

Rake::TestTask.new('test:activejob') do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.libs << "test/active_job"
  test.test_files = FileList['test/active_job/cases/*_test.rb']
end

task "env:aj_integration" do
  ENV["AJ_INTEGRATION_TESTS"] = "1"
end

Rake::TestTask.new('test:activejob:integration' => 'env:aj_integration') do |t|
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1")
    puts "Integration tests require Ruby 3.1 or later"
    exit 0
  end

  t.description = "Run integration tests for Resque::ActiveJob::Adapter"
  t.libs << "test"
  t.libs << "test/active_job"
  t.test_files = FileList["test/active_job/integration/**/*_test.rb"]
  t.verbose = true
  t.warning = true
end

if command? :kicker
  desc "Launch Kicker (like autotest)"
  task :kicker do
    puts "Kicking... (ctrl+c to cancel)"
    exec "kicker -e rake test lib examples"
  end
end


#
# Install
#

task :install => [ 'redis:install', 'dtach:install' ]


#
# Documentation
#

begin
  require 'sdoc_helpers'
rescue LoadError
end
