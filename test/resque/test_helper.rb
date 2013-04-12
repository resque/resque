require 'minitest/autorun'

##
# Add helper methods to Kernel
#
module Kernel
  def silence_warnings
    with_warnings(nil) { yield }
  end unless Kernel.respond_to?(:silence_warnings)

  def with_warnings(flag)
    old_verbose, $VERBOSE = $VERBOSE, flag
    yield
  ensure
    $VERBOSE = old_verbose
  end unless Kernel.respond_to?(:with_warnings)

  def jruby?
    defined?(JRUBY_VERSION)
  end
end
