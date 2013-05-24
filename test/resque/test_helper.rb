require 'simplecov'
SimpleCov.start do
  add_filter do |source_file|
    source_file.filename =~ /test/
  end
end

require 'coveralls'
Coveralls.wear!

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

class SelfLoggingTestJob
  def self.perform(logger_path)
    File.open(logger_path, "w+") do |fp|
      fp.write("SelfLoggingTestJob:#{Process.pid}")
    end
  end
end
