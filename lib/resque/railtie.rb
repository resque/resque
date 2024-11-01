module Resque
  class Railtie < Rails::Railtie
    rake_tasks do
      require 'resque/tasks'

      # redefine ths task to load the rails env
      task "resque:setup" => :environment
    end

    initializer "resque.active_job" do
      ActiveSupport.on_load(:active_job) do
        require "active_job/queue_adapters/resque_adapter"
        ActiveJob::Base.queue_adapter = :resque
      end
    end
  end
end
