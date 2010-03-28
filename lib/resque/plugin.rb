module Resque
  module Plugin

    # `extend_object` is like `extended` except that we now override
    # everything that happens when this module is extended.
    def extend_object(obj)
      var = :@plugins
      obj.instance_variable_set(var, []) unless obj.instance_variable_defined?(var)

      k = Class.new
      k.send(:include, self)
      obj.instance_variable_get(var) << k.new
    end
  end
end