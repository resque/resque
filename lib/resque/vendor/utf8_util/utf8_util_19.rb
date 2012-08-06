module UTF8Util
  def self.clean!(str)
    str.force_encoding("binary").encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => REPLACEMENT_CHAR)
  end
end
