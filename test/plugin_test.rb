require File.dirname(__FILE__) + '/test_helper'

context "Resque::Plugin finding hooks" do
  module SimplePlugin
    extend self
    def before_perform1; end
    def before_perform; end
    def before_perform2; end
    def after_perform1; end
    def after_perform; end
    def after_perform2; end
    def perform; end
    def around_perform1; end
    def around_perform; end
    def around_perform2; end
    def on_failure1; end
    def on_failure; end
    def on_failure2; end
  end

  test "before_perform hooks are found and sorted" do
    assert_equal ["before_perform", "before_perform1", "before_perform2"], Resque::Plugin.before_hooks(SimplePlugin)
  end

  test "after_perform hooks are found and sorted" do
    assert_equal ["after_perform", "after_perform1", "after_perform2"], Resque::Plugin.after_hooks(SimplePlugin)
  end

  test "around_perform hooks are found and sorted" do
    assert_equal ["around_perform", "around_perform1", "around_perform2"], Resque::Plugin.around_hooks(SimplePlugin)
  end

  test "on_failure hooks are found and sorted" do
    assert_equal ["on_failure", "on_failure1", "on_failure2"], Resque::Plugin.failure_hooks(SimplePlugin)
  end
end

