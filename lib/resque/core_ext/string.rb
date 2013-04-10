require 'active_support/inflector/methods'

class String
  def constantize
    ActiveSupport::Inflector.constantize(self)
  end
end
