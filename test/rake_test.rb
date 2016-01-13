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

  test "requires QUEUE environment variable" do
    begin
      run_rake_task
      fail 'Expected task to abort'
    rescue Exception => e
      assert_equal e.message, "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
      assert_equal e.class, SystemExit
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
