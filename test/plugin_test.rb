require 'test_helper'

describe "Resque::Plugin finding hooks" do
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
    def always1; end
    def always; end
    def always2; end
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
    assert_equal ["before_perform", "before_perform1", "before_perform2"], Resque::Plugin.before_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "after_perform hooks are found and sorted" do
    assert_equal ["after_perform", "after_perform1", "after_perform2"], Resque::Plugin.after_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "around_perform hooks are found and sorted" do
    assert_equal ["around_perform", "around_perform1", "around_perform2"], Resque::Plugin.around_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "on_failure hooks are found and sorted" do
    assert_equal ["on_failure", "on_failure1", "on_failure2"], Resque::Plugin.failure_hooks(SimplePlugin).map {|m| m.to_s}
  end

  it "always hooks are found and sorted" do
    assert_equal ["always", "always1", "always2"], Resque::Plugin.always_hooks(SimplePlugin).map(&:to_s)
  end

  it 'uses job.hooks if available get hook methods' do
    assert_equal ['around_perform_ok'], Resque::Plugin.around_hooks(HookBlacklistJob)
  end
end

describe "Resque::Plugin linting" do
  module ::BadBefore
    def self.before_perform; end
  end
  module ::BadAfter
    def self.after_perform; end
  end
  module ::BadAround
    def self.around_perform; end
  end
  module ::BadFailure
    def self.on_failure; end
  end

  it "before_perform must be namespaced" do
    begin
      Resque::Plugin.lint(BadBefore)
      assert false, "should have failed"
    rescue Resque::Plugin::LintError => e
      assert_equal "BadBefore.before_perform is not namespaced", e.message
    end
  end

  it "after_perform must be namespaced" do
    begin
      Resque::Plugin.lint(BadAfter)
      assert false, "should have failed"
    rescue Resque::Plugin::LintError => e
      assert_equal "BadAfter.after_perform is not namespaced", e.message
    end
  end

  it "around_perform must be namespaced" do
    begin
      Resque::Plugin.lint(BadAround)
      assert false, "should have failed"
    rescue Resque::Plugin::LintError => e
      assert_equal "BadAround.around_perform is not namespaced", e.message
    end
  end

  it "on_failure must be namespaced" do
    begin
      Resque::Plugin.lint(BadFailure)
      assert false, "should have failed"
    rescue Resque::Plugin::LintError => e
      assert_equal "BadFailure.on_failure is not namespaced", e.message
    end
  end

  module GoodBefore
    def self.before_perform1; end
  end
  module GoodAfter
    def self.after_perform1; end
  end
  module GoodAround
    def self.around_perform1; end
  end
  module GoodFailure
    def self.on_failure1; end
  end

  it "before_perform1 is an ok name" do
    Resque::Plugin.lint(GoodBefore)
  end

  it "after_perform1 is an ok name" do
    Resque::Plugin.lint(GoodAfter)
  end

  it "around_perform1 is an ok name" do
    Resque::Plugin.lint(GoodAround)
  end

  it "on_failure1 is an ok name" do
    Resque::Plugin.lint(GoodFailure)
  end
end
