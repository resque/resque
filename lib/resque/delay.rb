class Object
  def delay(options = {})
    if self.is_a?(Class) && instance_variable_get(:@queue).nil?
      extend Resque::ResquePerform
    elsif self.class.instance_variable_get(:@queue).nil?
      self.class.extend Resque::ResquePerform
    end

    Resque::DelayProxy.new(self)
  end
end

module Resque
  class DelayProxy
    attr_accessor :target

    def initialize(target_object)
      self.target = target_object
    end

    def method_missing(method, *args, &block)
      super(method, *args, &block) unless target.respond_to?(method)
      
      if target.is_a?(Class)
        Resque.enqueue(target, {'method' => method, 'args' => args})
      elsif target.respond_to?(:id) && target.class.respond_to?(:find)
        Resque.enqueue(target.class, {'id' => target.id, 'method' => method, 'args' => args})
      else
        raise "Unsupported #delay -- not a Class or an object who responds to #id & .find"
      end
    end
  end

  module ResquePerform
    def self.extended(base)
      return if base.instance_variable_get(:@queue).present?
      base.instance_variable_set(:@queue, base.to_s.underscore.downcase)
    end

    def perform(options)
      args = options['args']
      method = options['method']

      if options['id']
        find(options['id']).send(method, *args)
      else
        self.send(method, *args)
      end
    end
  end
end
