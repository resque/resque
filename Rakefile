#
# Setup
#

load 'tasks/redis.rake'
require 'rake/testtask'

$LOAD_PATH.unshift 'lib'
require 'resque/tasks'

def command?(command)
  system("type #{command} > /dev/null")
end


#
# Tests
#

task :default => :test

desc "Run the test suite"
task :test do
  rg = command?(:rg)
  Dir['test/**/*_test.rb'].each do |f|
    rg ? sh("rg #{f}") : ruby(f)
  end
end

if command? :kicker
  desc "Launch Kicker (like autotest)"
  task :kicker do
    puts "Kicking... (ctrl+c to cancel)"
    exec "kicker -e rake test lib examples"
  end
end


#
# Gem
#

task :install => [ 'redis:install', 'dtach:install' ]

begin
  require 'mg'
  MG.new("resque.gemspec")
rescue LoadError
  warn "mg not available."
  warn "Install it with: gem i mg"
end


#
# Documentation
#

begin
  require 'sdoc_helpers'
rescue LoadError
  puts "sdoc support not enabled. Please gem install sdoc-helpers."
end


#
# Publishing
#

desc "Push a new version to Gemcutter"
task :publish => "gem:publish" do
  require 'resque/version'

  sh "git tag v#{Resque::Version}"
  sh "git push origin v#{Resque::Version}"
  sh "git push origin master"
  sh "git clean -fd"
  exec "rake pages"
end
