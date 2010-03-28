module Resque
  # A Resque::Plugin may be used to extend your job class with extra behavior.
  # Plugins may implement any of the perform hooks defined by Resque::Job.
  #
  # A simple plugin looks like this.
  #
  #   module LogPerform
  #     extend Resque::Plugin
  #     def before_perform(*args)
  #       Logger.info "About to perform..."
  #     end
  #   end
  #
  # To use a plugin, just extend your job.
  #
  #  class MyJob
  #    extend LogPerform
  #    def self.perform(*args)
  #      do_stuff
  #    end
  #  end
  module Plugin

    # `extend_object` is like `extended` except that we now override
    # everything that happens when this module is extended.
    # http://ruby-doc.org/core/classes/Module.html#M001637
    def extend_object(obj)
      var = :@plugins
      obj.instance_variable_set(var, []) unless obj.instance_variable_defined?(var)

      k = Class.new
      k.send(:include, self)
      obj.instance_variable_get(var) << k.new
    end
  end
end