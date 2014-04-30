# encoding: utf-8
# Core extensions on Hash
class Hash
  unless method_defined?(:symbolize_keys)
    # Returns a duplicate of self with symbolized keys
    # Defined IFF not already defined elsewhere (e.g., ActiveSupport)
    # @return [Hash<Symbol,Object>]
    def symbolize_keys
      inject({}) do |options, (key, value)|
        options[(key.to_sym rescue key) || key] = value
        options
      end
    end
  end

  unless method_defined?(:symbolize_keys!)
    # Destructively replaces keys in self with symbolized keys
    # Defined IFF not already defined elsewhere (e.g., ActiveSupport)
    # @return [Hash<Symbol,Object>]
    def symbolize_keys!
      self.replace(self.symbolize_keys)
    end
  end

  unless method_defined?(:slice)
    # Returns a subset of self
    # Defined IFF not already defined elsewhere (e.g., ActiveSupport)
    # @param keys [Array<Object>]
    # @return [Hash<Object,Object>]
    def slice(*keys)
      hash = self.class.new
      keys.each { |k| hash[k] = self[k] if has_key?(k) }
      hash
    end
  end
end
