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

# shared examples taken from https://gist.github.com/jodosha/1560208

MiniTest::Spec.class_eval do
  def self.shared_examples
    @shared_examples ||= {}
  end
end

module MiniTest::Spec::SharedExamples
  def shared_examples_for(desc, &block)
    MiniTest::Spec.shared_examples[desc] = block
  end

  def it_behaves_like(desc)
    self.instance_eval do
      MiniTest::Spec.shared_examples[desc].call
    end
  end
end

Object.class_eval { include(MiniTest::Spec::SharedExamples) }
