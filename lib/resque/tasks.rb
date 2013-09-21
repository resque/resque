# require 'resque/tasks'
# will give you the resque tasks
require 'resque/cli'

namespace :resque do
  task :setup

  desc "Start a Resque worker"
  task :work => [ :preload, :setup ] do
    warn "DEPRECATION WARNING: Rake tasks are deprecated. Use `resque work` instead"

    opts = [
      "-q", ENV['QUEUES'] || ENV['QUEUE'] || "*",
      "-t", ENV['RESQUE_TERM_TIMEOUT'] || 4.0,
      "-d", !ENV['BACKGROUND'].nil?,
      "-p", ENV['PIDFILE'],
      "-i", ENV['INTERVAL'] || 5
    ]

    Resque::CLI.new([], opts).invoke(:work)
  end

  desc "Start multiple Resque workers. Should only be used in dev mode."
  task :workers do
    warn "DEPRECATION WARNING: Rake tasks are deprecated. Use `resque workers` instead"

    opts = [
      "-n", ENV['COUNT'] || 5
    ]

    Resque::CLI.new([], opts).invoke(:workers)
  end

  # Preload app files if this is Rails
  task :preload => :setup do
    if defined?(Rails) && Rails.respond_to?(:application)
      # Rails 3
      Rails.application.eager_load!
    elsif defined?(Rails::Initializer)
      # Rails 2.3
      $rails_rake_task = false
      Rails::Initializer.run :load_application_classes
    end
  end

  namespace :failures do
    desc "Sort the 'failed' queue for the redis_multi_queue failure backend"
    task :sort do
      warn "DEPRECATION WARNING: Rake tasks are deprecated. Use `resque sort_failures` instead"
      Resque::CLI.new.invoke(:sort_failures)
    end
  end
end
