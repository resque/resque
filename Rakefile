require 'rake/testtask'
eval File.read('tasks/redis.rake')
eval File.read('tasks/resque.rake')

task :default => :test

Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end
