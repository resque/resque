module Resque
  module Plugin
    extend self

    def before_hooks(job)
      job.methods.grep(/^before_perform/).sort
    end

    def around_hooks(job)
      job.methods.grep(/^around_perform/).sort
    end

    def after_hooks(job)
      job.methods.grep(/^after_perform/).sort
    end

    def failure_hooks(job)
      job.methods.grep(/^on_failure/).sort
    end

  end
end