module Resque
  class Railtie < Rails::Railtie
    rake_tasks do
      require 'resque/tasks'

      # redefine ths task to load the rails env
      task "resque:setup" => :environment
    end
  end
end
