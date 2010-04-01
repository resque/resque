module Resque
  module Plugin
    extend self

    LintError = Class.new(RuntimeError)

    # Ensure that your plugin conforms to good hook naming conventions.
    #
    #   Resque::Plugin.lint(MyResquePlugin)
    def lint(plugin)
      (before_hooks(plugin) + around_hooks(plugin) + after_hooks(plugin)).each do |hook|
        raise LintError, "#{plugin}.#{hook} is not namespaced" if hook =~ /perform$/
      end
      failure_hooks(plugin).each do |hook|
        raise LintError, "#{plugin}.#{hook} is not namespaced" if hook =~ /failure$/
      end
    end

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
