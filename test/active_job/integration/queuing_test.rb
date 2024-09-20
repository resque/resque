# frozen_string_literal: true

require "helper"
require "jobs/hello_job"
require "active_support/core_ext/numeric/time"

class QueuingTest < ActiveSupport::TestCase
  test "should run jobs enqueued on a listening queue" do
    TestJob.perform_later @id
    wait_for_jobs_to_finish_for(5.seconds)
    assert_job_executed
  end

  test "should not run jobs queued on a non-listening queue" do
    old_queue = TestJob.queue_name

    begin
      TestJob.queue_as :some_other_queue
      TestJob.perform_later @id
      wait_for_jobs_to_finish_for(2.seconds)
      assert_job_not_executed
    ensure
      TestJob.queue_name = old_queue
    end
  end

  test "resque JobWrapper should have instance variable queue" do
    job = ::HelloJob.set(wait: 5.seconds).perform_later
    hash = Resque.decode(Resque.find_delayed_selection { true }[0])
    assert_equal hash["queue"], job.queue_name
  end

  test "should not run job enqueued in the future" do
    TestJob.set(wait: 10.minutes).perform_later @id
    wait_for_jobs_to_finish_for(5.seconds)
    assert_job_not_executed
  rescue NotImplementedError
    pass
  end

  test "should run job enqueued in the future at the specified time" do
    TestJob.set(wait: 5.seconds).perform_later @id
    wait_for_jobs_to_finish_for(2.seconds)
    assert_job_not_executed
    wait_for_jobs_to_finish_for(10.seconds)
    assert_job_executed
  rescue NotImplementedError
    pass
  end

  test "should run job bulk enqueued in the future at the specified time" do
    ActiveJob.perform_all_later([TestJob.new(@id).set(wait: 5.seconds)])
    wait_for_jobs_to_finish_for(2.seconds)
    assert_job_not_executed
    wait_for_jobs_to_finish_for(10.seconds)
    assert_job_executed
  rescue NotImplementedError
    pass
  end

 test "current locale is kept while running perform_later" do
    I18n.available_locales = [:en, :de]
    I18n.locale = :de

    TestJob.perform_later @id
    wait_for_jobs_to_finish_for(5.seconds)
    assert_job_executed
    assert_equal "de", job_executed_in_locale
  ensure
    I18n.available_locales = [:en]
    I18n.locale = :en
  end

  test "current timezone is kept while running perform_later" do
    current_zone = Time.zone
    Time.zone = "Hawaii"

    TestJob.perform_later @id
    wait_for_jobs_to_finish_for(5.seconds)
    assert_job_executed
    assert_equal "Hawaii", job_executed_in_timezone
  ensure
    Time.zone = current_zone
  end

  private
    def assert_job_executed(id = @id)
      assert job_executed(id), "Job #{id} was not executed"
    end

    def assert_job_not_executed(id = @id)
      assert_not job_executed(id), "Job #{id} was executed"
    end

    def assert_job_executed_before(first_id, second_id)
      assert job_executed_at(first_id) < job_executed_at(second_id), "Job #{first_id} was not executed before Job #{second_id}"
    end
end
