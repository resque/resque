$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'
require 'resque'

##
# test/spec/mini 2
# http://gist.github.com/25455
# chris@ozmm.org
#
def context(*args, &block)
  return super unless (name = args.first) && block
  require 'test/unit'
  klass = Class.new(defined?(ActiveSupport::TestCase) ? ActiveSupport::TestCase : Test::Unit::TestCase) do
    def self.test(name, &block)
      define_method("test_#{name.gsub(/\W/,'_')}", &block) if block
    end
    def self.xtest(*args) end
    def self.setup(&block) define_method(:setup, &block) end
    def self.teardown(&block) define_method(:teardown, &block) end
  end
  klass.class_eval &block
end

class SomeJob < Struct.new(:repo_id, :path)
end

class BadJob
  def perform
    raise "Bad job!"
  end
end

class GoodJob < Struct.new(:name)
  def perform
    "Good job, #{name}"
  end
end
