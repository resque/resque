require "rake"
require "test_helper"
require "mocha"

describe "rake tasks" do
  before do
    Rake.application.rake_require "tasks/resque"
  end

  describe 'resque:work' do

    it "requires QUEUE environment variable" do
      begin
        run_rake_task("resque:work")
        fail 'Expected task to abort'
      rescue Exception => e
        assert_equal e.message, "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
        assert_equal e.class, SystemExit
      end
    end

    it "works when multiple queues specified" do
      begin
        old_queues = ENV["QUEUES"]
        ENV["QUEUES"] = "high,low"
        Resque::Worker.any_instance.expects(:work)
        run_rake_task("resque:work")
      ensure
        ENV["QUEUES"] = old_queues
      end
    end

  end

  def run_rake_task(name)
    Rake::Task[name].reenable
    Rake.application.invoke_task(name)
  end

end
