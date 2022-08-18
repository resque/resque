module UTF8Util
  # use '?' instead of the unicode replace char, since that is 3 bytes
  # and can increase the string size if it's done a lot
  REPLACEMENT_CHAR = "?"

  # Replace invalid UTF-8 character sequences with a replacement character
  #
  # Returns self as valid UTF-8.
  def self.clean!(str)
    return str if str.encoding.to_s == "UTF-8"
    str.force_encoding("binary").encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => REPLACEMENT_CHAR)
  end

  # Replace invalid UTF-8 character sequences with a replacement character
  #
  # Returns a copy of this String as valid UTF-8.
  def self.clean(str)
    clean!(str.dup)
  end
end
