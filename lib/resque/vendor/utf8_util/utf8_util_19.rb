module UTF8Util
  class << self
    remove_method(:clean!) if method_defined?(:clean!)
  end

  def self.clean!(str)
    str.force_encoding("binary").encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => REPLACEMENT_CHAR)
  end
end
