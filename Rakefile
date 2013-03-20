require 'rubygems'
require 'bundler/setup'
require 'bundler/gem_tasks'
require 'resque/tasks'
require 'rake/testtask'
require 'yard'

Rake::TestTask.new do |test|
  test.verbose = true
  test.libs << "test/legacy"
  test.libs << "lib"
  test.test_files = FileList['test/resque/**/*_test.rb']
end

Rake::TestTask.new(:legacy) do |test|
  test.libs << "test/legacy"
  test.libs << "lib"
  test.test_files = FileList['test/legacy/**/*_test.rb']
end

Rake::TestTask.new(:end_to_end) do |test|
  test.libs << "test/end_to_end"
  test.libs << "lib"
  test.test_files = FileList['test/end_to_end/**/*_test.rb']
end

task :ci => [:test, :end_to_end, :legacy]

YARD::Rake::YardocTask.new
task :docs => :yard

task :default => :ci
