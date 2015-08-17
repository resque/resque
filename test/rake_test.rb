require "rake"
require "test_helper"
require "mocha"

context "rake" do
  setup do
    Rake.application.rake_require "tasks/resque"
  end

  def run_rake_task
    Rake::Task["resque:work"].reenable
    Rake.application.invoke_task "resque:work"
  end

  test "requires queue" do
    assert_raises Resque::NoQueueError do
      run_rake_task
    end
  end

  test "works when multiple queues specified" do
    begin
      old_queues = ENV["QUEUES"]
      ENV["QUEUES"] = "high,low"
      Resque::Worker.any_instance.expects(:work)
      run_rake_task
    ensure
      ENV["QUEUES"] = old_queues
    end
  end
end
