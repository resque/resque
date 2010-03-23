require File.dirname(__FILE__) + '/test_helper'

module PerformJob
  def perform_job(klass, *args)
    resque_job = Resque::Job.new(:testqueue, 'class' => klass, 'args' => args)
    resque_job.perform
  end
end

context "Resque::Job before_perform" do
  include PerformJob

  setup do
    Resque.redis.flush_all
  end

  class BeforePerformJob
    def self.before_perform(history)
      history << :before_perform
    end
    def self.perform(history)
      history << :perform
    end
  end

  test "it runs before_perform before perform" do
    result = perform_job(BeforePerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal history, [:before_perform, :perform]
  end

  class BeforePerformJobFails
    def self.before_perform(history)
      history << :before_perform
      raise StandardError
    end
    def self.perform(history)
      history << :perform
    end
  end

  test "raises an error and does not perform if before_perform fails" do
    history = []
    assert_raises StandardError do
      result = perform_job(BeforePerformJobFails, history)
      assert_equal false, result, "perform returned false"
    end
    assert_equal history, [:before_perform], "Only before_perform was run"
  end

  class BeforePerformJobAborts
    def self.before_perform(history)
      history << :before_perform
      raise Resque::Job::DontPerform
    end
    def self.perform(history)
      history << :perform
    end
  end

  test "does not perform if before_perform raises Resque::Job::DontPerform" do
    result = perform_job(BeforePerformJobAborts, history=[])
    assert_equal false, result, "perform returned false"
    assert_equal history, [:before_perform], "Only before_perform was run"
  end

end
