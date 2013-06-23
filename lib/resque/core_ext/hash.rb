class Hash
  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end unless method_defined?(:symbolize_keys)

  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end unless method_defined?(:symbolize_keys!)

  def slice(*keys)
    hash = self.class.new
    keys.each { |k| hash[k] = self[k] if has_key?(k) }
    hash
  end unless method_defined?(:slice)
end
