require File.dirname(__FILE__) + '/test_helper'

context "Multiple plugins with multiple callbacks" do
  include PerformJob

  module Plugin1
    def before_perform_record_history(history)
      history << :before_one
    end
    def after_perform_record_history(history)
      history << :after_one
    end
  end

  module Plugin2
    def before_perform_record_history2(history)
      history << :before_two
    end
    def after_perform_record_history2(history)
      history << :after_two
    end
  end

  class ManyBeforesJob
    extend Plugin1
    extend Plugin2
    def self.perform(history)
      history << :perform
    end
  end

  test "all plugins are executed in order" do
    result = perform_job(ManyBeforesJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:before_one, :before_two, :perform, :after_one, :after_two], history
  end
end

context "Resque::Plugin before_perform" do
  include PerformJob

  module BeforePerform
    def before_perform_record_history(history)
      history << :before_perform_plugin
    end
  end

  class BeforePerformJob
    extend BeforePerform
    def self.perform(history)
      history << :perform
    end
    def self.before_perform(history)
      history << :before_perform
    end
  end

  test "before_perform is executed in plugins first, then the job" do
    result = perform_job(BeforePerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:before_perform_plugin, :before_perform, :perform], history
  end
end

context "Resque::Plugin after_perform" do
  include PerformJob

  module AfterPerform
    def after_perform_record_history(history)
      history << :after_perform_plugin
    end
  end

  class AfterPerformJob
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_record_history2(history)
      history << :after_perform
    end
  end

  test "after_perform is executed in plugins first, then the job" do
    result = perform_job(AfterPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:perform, :after_perform_plugin, :after_perform], history
  end
end

context "Resque::Plugin around_perform" do
  include PerformJob

  module AroundPerform
    def around_perform_record_history(history)
      history << :around_perform_plugin
      yield
    end
  end

  class AroundPerformJustPerformsJob
    extend AroundPerform
    def self.perform(history)
      history << :perform
    end
  end

  test "around_perform is executed in plugins first, then the job is executed" do
    result = perform_job(AroundPerformJustPerformsJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_plugin, :perform], history
  end

  class AroundPerformJob
    extend AroundPerform
    def self.perform(history)
      history << :perform
    end
    def self.around_perform(history)
      history << :around_perform
      yield
    end
  end

  test "around_perform is executed in plugins first, then the job" do
    result = perform_job(AroundPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_plugin, :around_perform, :perform], history
  end

  module AroundPerform2
    def around_perform_record_history2(history)
      history << :around_perform_plugin2
      yield
    end
  end

  class AroundPerformJob2
    extend AroundPerform
    extend AroundPerform2
    def self.perform(history)
      history << :perform
    end
    def self.around_perform(history)
      history << :around_perform
      yield
    end
  end

  test "around_perform is executed in multiple plugins first, then the job" do
    result = perform_job(AroundPerformJob2, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_plugin, :around_perform_plugin2, :around_perform, :perform], history
  end

  module AroundPerformDoesNotYield
    def around_perform_without_yield(history)
      history << :around_perform_plugin_no_yield
    end
  end

  class AroundPerformJob3
    extend AroundPerform
    extend AroundPerformDoesNotYield
    extend AroundPerform2
    def self.perform(history)
      history << :perform
    end
    def self.around_perform(history)
      history << :around_perform
      yield
    end
  end

  test "around_perform is executed in multiple plugins but the job aborts if all plugins do not yield" do
    result = perform_job(AroundPerformJob3, history=[])
    assert_equal false, result, "perform returned false"
    assert_equal [:around_perform_plugin, :around_perform_plugin_no_yield], history
  end
end

context "Resque::Plugin on_failure" do
  include PerformJob

  module OnFailure
    def on_failure_record_history(exception, history)
      history << "#{exception.message} plugin"
    end
  end

  class FailureJob
    extend OnFailure
    def self.perform(history)
      history << :perform
      raise StandardError, "oh no"
    end
    def self.on_failure(exception, history)
      history << exception.message
    end
  end

  test "after_perform is executed in plugins first, then the job" do
    history = []
    assert_raises StandardError do
      perform_job(FailureJob, history)
    end
    assert_equal [:perform, "oh no plugin", "oh no"], history
  end
end
