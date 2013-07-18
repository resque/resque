require 'rubygems'
require 'bundler/setup'
require 'bundler/gem_tasks'
require 'resque/tasks'
require 'rake/testtask'
require 'yard'

Rake::TestTask.new do |test|
  test.libs << "test/resque"
  test.libs << "lib"
  test.test_files = FileList['test/resque/**/*_test.rb']
end

Rake::TestTask.new(:legacy) do |test|
  test.libs << "test/legacy"
  test.libs << "lib"
  test.test_files = FileList['test/legacy/**/*_test.rb']
end

Rake::TestTask.new(:verbose_test) do |test|
  test.verbose = true
  test.libs << "test/resque"
  test.libs << "lib"
  test.test_files = FileList['test/resque/**/*_test.rb']
  test.ruby_opts = ["-w"]
end

Rake::TestTask.new(:verbose_legacy) do |test|
  test.libs << "test/legacy"
  test.libs << "lib"
  test.test_files = FileList['test/legacy/**/*_test.rb']
  test.ruby_opts = ["-w"]
end

task :ci => [:verbose_test, :verbose_legacy]

YARD::Rake::YardocTask.new
task :docs => :yard

task :default => [:test, :legacy]
