module UTF8Util
  # use '?' intsead of the unicode replace char, since that is 3 bytes
  # and can increase the string size if it's done a lot
  REPLACEMENT_CHAR = "?"

  # Replace invalid UTF-8 character sequences with a replacement character
  #
  # Returns self as valid UTF-8.
  def self.clean!(str)
    raise NotImplementedError
  end

  # Replace invalid UTF-8 character sequences with a replacement character
  #
  # Returns a copy of this String as valid UTF-8.
  def self.clean(str)
    clean!(str.dup)
  end

end

if RUBY_VERSION <= '1.9'
  require 'resque/vendor/utf8_util/utf8_util_18'
else
  require 'resque/vendor/utf8_util/utf8_util_19'
end
