require "rake"
require "test_helper"
require "mocha"

describe "rake tasks" do
  before do
    Rake.application.rake_require "tasks/resque"
  end

  after do
    ENV['QUEUES'] = nil
    ENV['VVERBOSE'] = nil
    ENV['VERBOSE'] = nil
  end

  describe 'resque:work' do

    it "requires QUEUE environment variable" do
      assert_system_exit("set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work") do
        run_rake_task("resque:work")
      end
    end

    it "works when multiple queues specified" do
      ENV["QUEUES"] = "high,low"
      Resque::Worker.any_instance.expects(:work)
      run_rake_task("resque:work")
    end

    describe 'log output' do
      let(:messages) { StringIO.new }

      before do
        Resque.logger = Logger.new(messages)
        Resque.logger.level = Logger::ERROR
        Resque.enqueue_to(:jobs, SomeJob, 20, '/tmp')
        Resque::Worker.any_instance.stubs(:shutdown?).returns(false, true) # Process one job and then quit
      end

      it "triggers DEBUG level logging when VVERBOSE is set to 1" do
        ENV['VVERBOSE'] = '1'
        ENV['QUEUES'] = 'jobs'
        run_rake_task("resque:work")
        assert_includes messages.string, 'Starting worker' # Include an info level statement
        assert_includes messages.string, 'Registered signals' # Includes a debug level statement
      end

      it "triggers INFO level logging when VERBOSE is set to 1" do
        ENV['VERBOSE'] = '1'
        ENV['QUEUES'] = 'jobs'
        run_rake_task("resque:work")
        assert_includes messages.string, 'Starting worker' # Include an info level statement
        refute_includes messages.string, 'Registered signals' # Does not a debug level statement
      end
    end

  end

  describe 'resque:workers' do

    it 'requires COUNT environment variable' do
      assert_system_exit("set COUNT env var, e.g. $ COUNT=2 rake resque:workers") do
        run_rake_task("resque:workers")
      end
    end

  end

  def run_rake_task(name)
    Rake::Task[name].reenable
    Rake.application.invoke_task(name)
  end

  def assert_system_exit(expected_message)
    begin
      capture_io { yield }
      fail 'Expected task to abort'
    rescue Exception => e
      assert_equal e.message, expected_message
      assert_equal e.class, SystemExit
    end
  end

end
