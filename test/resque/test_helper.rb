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

module WorkerTestHelper
  def self.pause(worker)
    IO.pipe do |r,w|
      rd, wr = IO.pipe

      Thread.start { sleep(0.5); wr.write 'x'; w.write 'x' }

      IO.stub(:pipe, [rd,wr]) do
        begin
          worker.pause
        ensure
          wr.write 'x' unless rd.closed?
        end
      end

      r.read 1
    end
  end
end
