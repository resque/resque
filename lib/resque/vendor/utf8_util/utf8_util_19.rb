module UTF8Util
  def self.clean!(str)
    return str if str.encoding.to_s == "UTF-8"
    str.force_encoding("binary").encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => REPLACEMENT_CHAR)
  end
end
