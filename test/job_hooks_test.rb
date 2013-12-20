require 'test_helper'

context "Resque::Job before_perform" do
  include PerformJob

  class ::BeforePerformJob
    def self.before_perform_record_history(history)
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

  class ::BeforePerformJobFails
    def self.before_perform_fail_job(history)
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
      perform_job(BeforePerformJobFails, history)
    end
    assert_equal history, [:before_perform], "Only before_perform was run"
  end

  class ::BeforePerformJobAborts
    def self.before_perform_abort(history)
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

context "Resque::Job after_perform" do
  include PerformJob

  class ::AfterPerformJob
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_record_history(history)
      history << :after_perform
    end
  end

  test "it runs after_perform after perform" do
    result = perform_job(AfterPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal history, [:perform, :after_perform]
  end

  class ::AfterPerformJobFails
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_fail_job(history)
      history << :after_perform
      raise StandardError
    end
  end

  test "raises an error but has already performed if after_perform fails" do
    history = []
    assert_raises StandardError do
      perform_job(AfterPerformJobFails, history)
    end
    assert_equal history, [:perform, :after_perform], "Only after_perform was run"
  end
end

context "Resque::Job around_perform" do
  include PerformJob

  class ::AroundPerformJob
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_record_history(history)
      history << :start_around_perform
      yield
      history << :finish_around_perform
    end
  end

  test "it runs around_perform then yields in order to perform" do
    result = perform_job(AroundPerformJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal history, [:start_around_perform, :perform, :finish_around_perform]
  end

  class ::AroundPerformJobFailsBeforePerforming
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_fail(history)
      history << :start_around_perform
      raise StandardError
      yield
      history << :finish_around_perform
    end
  end

  test "raises an error and does not perform if around_perform fails before yielding" do
    history = []
    assert_raises StandardError do
      perform_job(AroundPerformJobFailsBeforePerforming, history)
    end
    assert_equal history, [:start_around_perform], "Only part of around_perform was run"
  end

  class ::AroundPerformJobFailsWhilePerforming
    def self.perform(history)
      history << :perform
      raise StandardError
    end
    def self.around_perform_fail_in_yield(history)
      history << :start_around_perform
      begin
        yield
      ensure
        history << :ensure_around_perform
      end
      history << :finish_around_perform
    end
  end

  test "raises an error but may handle exceptions if perform fails" do
    history = []
    assert_raises StandardError do
      perform_job(AroundPerformJobFailsWhilePerforming, history)
    end
    assert_equal history, [:start_around_perform, :perform, :ensure_around_perform], "Only part of around_perform was run"
  end

  class ::AroundPerformJobDoesNotHaveToYield
    def self.perform(history)
      history << :perform
    end
    def self.around_perform_dont_yield(history)
      history << :start_around_perform
      history << :finish_around_perform
    end
  end

  test "around_perform is not required to yield" do
    history = []
    result = perform_job(AroundPerformJobDoesNotHaveToYield, history)
    assert_equal false, result, "perform returns false"
    assert_equal history, [:start_around_perform, :finish_around_perform], "perform was not run"
  end
end

context "Resque::Job on_failure" do
  include PerformJob

  class ::FailureJobThatDoesNotFail
    def self.perform(history)
      history << :perform
    end
    def self.on_failure_record_failure(exception, history)
      history << exception.message
    end
  end

  test "it does not call on_failure if no failures occur" do
    result = perform_job(FailureJobThatDoesNotFail, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal history, [:perform]
  end

  class ::FailureJobThatFails
    def self.perform(history)
      history << :perform
      raise StandardError, "oh no"
    end
    def self.on_failure_record_failure(exception, history)
      history << exception.message
    end
  end

  test "it calls on_failure with the exception and then re-raises the exception" do
    history = []
    assert_raises StandardError do
      perform_job(FailureJobThatFails, history)
    end
    assert_equal history, [:perform, "oh no"]
  end

  class ::FailureJobThatFailsBadly
    def self.perform(history)
      history << :perform
      raise SyntaxError, "oh no"
    end
    def self.on_failure_record_failure(exception, history)
      history << exception.message
    end
  end

  test "it calls on_failure even with bad exceptions" do
    history = []
    assert_raises SyntaxError do
      perform_job(FailureJobThatFailsBadly, history)
    end
    assert_equal history, [:perform, "oh no"]
  end
end

context "Resque::Job after_enqueue" do
  include PerformJob

  class ::AfterEnqueueJob
    @queue = :jobs
    def self.after_enqueue_record_history(history)
      history << :after_enqueue
    end

    def self.perform(history)
    end
  end

  test "the after enqueue hook should run" do
    history = []
    @worker = Resque::Worker.new(:jobs)
    Resque.enqueue(AfterEnqueueJob, history)
    @worker.work(0)
    assert_equal history, [:after_enqueue], "after_enqueue was not run"
  end
end


context "Resque::Job before_enqueue" do
  include PerformJob

  class ::BeforeEnqueueJob
    @queue = :jobs
    def self.before_enqueue_record_history(history)
      history << :before_enqueue
    end

    def self.perform(history)
    end
  end

  class ::BeforeEnqueueJobAbort
    @queue = :jobs
    def self.before_enqueue_abort(history)
      false
    end

    def self.perform(history)
    end
  end

  test "the before enqueue hook should run" do
    history = []
    @worker = Resque::Worker.new(:jobs)
    assert Resque.enqueue(BeforeEnqueueJob, history)
    @worker.work(0)
    assert_equal history, [:before_enqueue], "before_enqueue was not run"
  end

  test "a before enqueue hook that returns false should prevent the job from getting queued" do
    Resque.remove_queue(:jobs)
    history = []
    @worker = Resque::Worker.new(:jobs)
    assert_nil Resque.enqueue(BeforeEnqueueJobAbort, history)
    assert_equal 0, Resque.size(:jobs)
  end
end

context "Resque::Job after_dequeue" do
  include PerformJob

  class ::AfterDequeueJob
    @queue = :jobs
    def self.after_dequeue_record_history(history)
      history << :after_dequeue
    end

    def self.perform(history)
    end
  end

  test "the after dequeue hook should run" do
    history = []
    @worker = Resque::Worker.new(:jobs)
    Resque.dequeue(AfterDequeueJob, history)
    @worker.work(0)
    assert_equal history, [:after_dequeue], "after_dequeue was not run"
  end
end


context "Resque::Job before_dequeue" do
  include PerformJob

  class ::BeforeDequeueJob
    @queue = :jobs
    def self.before_dequeue_record_history(history)
      history << :before_dequeue
    end

    def self.perform(history)
    end
  end

  class ::BeforeDequeueJobAbort
    @queue = :jobs
    def self.before_dequeue_abort(history)
      false
    end

    def self.perform(history)
    end
  end

  test "the before dequeue hook should run" do
    history = []
    @worker = Resque::Worker.new(:jobs)
    Resque.dequeue(BeforeDequeueJob, history)
    @worker.work(0)
    assert_equal history, [:before_dequeue], "before_dequeue was not run"
  end

  test "a before dequeue hook that returns false should prevent the job from getting dequeued" do
    history = []
    assert_equal nil, Resque.dequeue(BeforeDequeueJobAbort, history)
  end
end

context "Resque::Job all hooks" do
  include PerformJob

  class ::VeryHookyJob
    def self.before_perform_record_history(history)
      history << :before_perform
    end
    def self.around_perform_record_history(history)
      history << :start_around_perform
      yield
      history << :finish_around_perform
    end
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_record_history(history)
      history << :after_perform
    end
    def self.on_failure_record_history(exception, history)
      history << exception.message
    end
  end

  test "the complete hook order" do
    result = perform_job(VeryHookyJob, history=[])
    assert_equal true, result, "perform returned true"
    assert_equal history, [
      :before_perform,
      :start_around_perform,
      :perform,
      :finish_around_perform,
      :after_perform
    ]
  end

  class ::VeryHookyJobThatFails
    def self.before_perform_record_history(history)
      history << :before_perform
    end
    def self.around_perform_record_history(history)
      history << :start_around_perform
      yield
      history << :finish_around_perform
    end
    def self.perform(history)
      history << :perform
    end
    def self.after_perform_record_history(history)
      history << :after_perform
      raise StandardError, "oh no"
    end
    def self.on_failure_record_history(exception, history)
      history << exception.message
    end
  end

  test "the complete hook order with a failure at the last minute" do
    history = []
    assert_raises StandardError do
      perform_job(VeryHookyJobThatFails, history)
    end
    assert_equal history, [
      :before_perform,
      :start_around_perform,
      :perform,
      :finish_around_perform,
      :after_perform,
      "oh no"
    ]
  end

  class ::CallbacksInline
    @queue = :callbacks_inline

    def self.before_perform_record_history(history, count)
      history << :before_perform
      count['count'] += 1
    end

    def self.after_perform_record_history(history, count)
      history << :after_perform
      count['count'] += 1
    end

    def self.around_perform_record_history(history, count)
      history << :start_around_perform
      count['count'] += 1
      yield
      history << :finish_around_perform
      count['count'] += 1
    end

    def self.perform(history, count)
      history << :perform
      $history = history
      $count = count
    end
  end

  test "it runs callbacks when inline is true" do
    begin
      Resque.inline = true
      # Sending down two parameters that can be passed and updated by reference
      result = Resque.enqueue(CallbacksInline, [], {'count' => 0})
      assert_equal true, result, "perform returned true"
      assert_equal $history, [:before_perform, :start_around_perform, :perform, :finish_around_perform, :after_perform]
      assert_equal 4, $count['count']
    ensure
      Resque.inline = false
    end
  end
end
