require 'rubygems'
require 'bundler/setup'
require 'bundler/gem_tasks'
require 'resque/tasks'
require 'rake/testtask'
require 'yard'

Rake::TestTask.new

Rake::TestTask.new(:legacy) do |test|
  test.verbose = true
  test.libs << "test/legacy"
  test.libs << "lib"
  test.test_files = FileList['test/legacy/**/*_test.rb']
end

task :ci => [:test, :legacy]

YARD::Rake::YardocTask.new
task :docs => :yard

task :default => :ci
