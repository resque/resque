require 'test_helper'

describe "Multiple plugins with multiple hooks" do
  include PerformJob

  module Plugin1
    def before_perform_record_history1(history)
      history << :before1
    end
    def after_perform_record_history1(history)
      history << :after1
    end
  end

  module Plugin2
    def before_perform_record_history2(history)
      history << :before2
    end
    def after_perform_record_history2(history)
      history << :after2
    end
  end

  class ::ManyBeforesJob
    extend Plugin1
    extend Plugin2
    def self.perform(history)
      history << :perform
    end
  end

  it "hooks of each type are executed in alphabetical order" do
    result = perform_job(ManyBeforesJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:before1, :before2, :perform, :after1, :after2], history
  end
end

describe "Resque::Plugin ordering before_perform" do
  include PerformJob

  module BeforePerformPlugin
    def before_perform_plugin(history)
      history << :before_perform_plugin
    end
  end

  class ::JobPluginsTestBeforePerformJob
    extend BeforePerformPlugin
    def self.perform(history)
      history << :perform
    end
    def self.before_perform_job(history)
      history << :before_perform_job
    end
  end

  it "before_perform hooks are executed in order" do
    result = perform_job(JobPluginsTestBeforePerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:before_perform_job, :before_perform_plugin, :perform], history
  end
end

describe "Resque::Plugin ordering after_perform" do
  include PerformJob

  module AfterPerformPlugin
    def after_perform_record_history(history)
      history << :after_perform_plugin
    end
  end

  class ::JobPluginsTestAfterPerformJob
    extend AfterPerformPlugin
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_job(history)
      history << :after_perform_job
    end
  end

  it "after_perform hooks are executed in order" do
    result = perform_job(JobPluginsTestAfterPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:perform, :after_perform_job, :after_perform_plugin], history
  end
end

describe "Resque::Plugin ordering around_perform" do
  include PerformJob

  module AroundPerformPlugin1
    def around_perform_plugin1(history)
      history << :around_perform_plugin1
      yield
    end
  end

  class ::AroundPerformJustPerformsJob
    extend AroundPerformPlugin1
    def self.perform(history)
      history << :perform
    end
  end

  it "around_perform hooks are executed before the job" do
    result = perform_job(AroundPerformJustPerformsJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_plugin1, :perform], history
  end

  class ::JobPluginsTestAroundPerformJob
    extend AroundPerformPlugin1
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_job(history)
      history << :around_perform_job
      yield
    end
  end

  it "around_perform hooks are executed in order" do
    result = perform_job(JobPluginsTestAroundPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_job, :around_perform_plugin1, :perform], history
  end

  module AroundPerformPlugin2
    def around_perform_plugin2(history)
      history << :around_perform_plugin2
      yield
    end
  end

  class ::AroundPerformJob2
    extend AroundPerformPlugin1
    extend AroundPerformPlugin2
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_job(history)
      history << :around_perform_job
      yield
    end
  end

  it "many around_perform are executed in order" do
    result = perform_job(AroundPerformJob2, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal [:around_perform_job, :around_perform_plugin1, :around_perform_plugin2, :perform], history
  end

  module AroundPerformDoesNotYield
    def around_perform_plugin(history)
      history << :around_perform_plugin
    end
  end

  class ::AroundPerformJob3
    extend AroundPerformPlugin1
    extend AroundPerformPlugin2
    extend AroundPerformDoesNotYield
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_job(history)
      history << :around_perform_job
      yield
    end
  end

  it "the job is aborted if an around_perform hook does not yield" do
    result = perform_job(AroundPerformJob3, history=[])
    assert_equal false, result, "perform returned false"
    assert_equal [:around_perform_job, :around_perform_plugin], history
  end

  module AroundPerformGetsJobResult
    @@result = nil
    def last_job_result
      @@result
    end

    def around_perform_gets_job_result(*args)
      @@result = yield
    end
  end

  class ::AroundPerformJobWithReturnValue < GoodJob
    extend AroundPerformGetsJobResult
  end

  it "the job is not aborted if an around_perform hook does yield" do
    result = perform_job(AroundPerformJobWithReturnValue, 'Bob')
    assert_equal true, result, "perform returned true"
    assert_equal 'Good job, Bob', AroundPerformJobWithReturnValue.last_job_result
  end
end

describe "Resque::Plugin ordering on_failure" do
  include PerformJob

  module OnFailurePlugin
    def on_failure_plugin(exception, history)
      history << "#{exception.message} plugin"
    end
  end

  class ::FailureJob
    extend OnFailurePlugin
    def self.perform(history)
      history << :perform
      raise StandardError, "oh no"
    end
    def self.on_failure_job(exception, history)
      history << exception.message
    end
  end

  it "on_failure hooks are executed in order" do
    history = []
    assert_raises StandardError do
      perform_job(FailureJob, history)
    end
    assert_equal [:perform, "oh no", "oh no plugin"], history
  end
end
