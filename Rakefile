require 'rubygems'

begin
  require 'bundler/setup'
rescue LoadError => e
  warn e.message
  warn "Run `gem install bundler` to install Bundler"
  exit -1
end

#
# Bundler
#
require 'bundler/gem_tasks'

#
# Setup
#
$LOAD_PATH.unshift 'lib'
require 'resque/tasks'

def command?(command)
  system("type #{command} > /dev/null 2>&1")
end


#
# Tests
#
require 'rake/testtask'

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test"
  test.libs << "lib"
  test.test_files = FileList['test/**/*_test.rb']
end
task :default => :test

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
require 'yard'
YARD::Rake::YardocTask.new
task :docs => :yard
