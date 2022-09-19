require 'test_helper'

describe "Resque::Plugin finding hooks" do
  module SimplePlugin
    extend self
    def before_perform_second; end
    def before_perform_first; end
    def before_perform_third; end
    def after_perform_second; end
    def after_perform_first; end
    def after_perform_third; end
    def perform; end
    def around_perform_second; end
    def around_perform_first; end
    def around_perform_third; end
    def on_failure_second; end
    def on_failure_first; end
    def on_failure_third; end
  end

  module HookBlacklistJob
    extend self
    def around_perform_blacklisted; end
    def around_perform_ok; end

    def hooks
      @hooks ||= Resque::Plugin.job_methods(self) - ['around_perform_blacklisted']
    end
  end

  it "before_perform hooks are found and sorted" do
    assert_equal ["before_perform_first", "before_perform_second", "before_perform_third"], Resque::Plugin.before_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "after_perform hooks are found and sorted" do
    assert_equal ["after_perform_first", "after_perform_second", "after_perform_third"], Resque::Plugin.after_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "around_perform hooks are found and sorted" do
    assert_equal ["around_perform_first", "around_perform_second", "around_perform_third"], Resque::Plugin.around_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "on_failure hooks are found and sorted" do
    assert_equal ["on_failure_first", "on_failure_second", "on_failure_third"], Resque::Plugin.failure_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it 'uses job.hooks if available get hook methods' do
    assert_equal ['around_perform_ok'], Resque::Plugin.around_hooks(HookBlacklistJob)
  end
end
