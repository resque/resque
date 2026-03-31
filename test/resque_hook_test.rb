require 'test_helper'
require 'tempfile'

describe "Resque Hooks" do
  class CallNotifyJob
    def self.perform
      $called = true
    end
  end

  before do
    $called = false
    @worker = Resque::Worker.new(:jobs)
  end

  describe "which hooks run in which process" do
    def assert_hook_runs_in_process(hook_name, in_parent:, run_before_work:)
      file = Tempfile.new("resque_#{hook_name}_pid")
      Resque.send(hook_name) { File.write(file.path, Process.pid.to_s) }
      run_before_work.call
      Resque::Job.create(:jobs, CallNotifyJob)
      @worker.work(0)
      content = File.read(file.path).strip
      refute_empty content, "`#{hook_name}` hook was not called"
      if in_parent
        assert_equal $TEST_PID, content.to_i
      else
        refute_equal $TEST_PID, content.to_i
      end
    ensure
      file&.delete
    end

    def assert_hook_runs_in_parent(hook_name, run_before_work = -> {})
      assert_hook_runs_in_process(hook_name, in_parent: true, run_before_work:)
    end

    def assert_hook_runs_in_worker(hook_name, run_before_work = -> {})
      assert_hook_runs_in_process(hook_name, in_parent: false, run_before_work:)
    end

    it "runs before_first_fork hook in the parent process" do
      assert_hook_runs_in_parent(:before_first_fork)
    end

    it "runs before_fork hook in the parent process" do
      assert_hook_runs_in_parent(:before_fork)
    end

    it "runs after_fork hook in the child process" do
      assert_hook_runs_in_worker(:after_fork)
    end

    it "runs queue_empty hook in the parent process" do
      assert_hook_runs_in_parent(:queue_empty)
    end

    it "runs shutdown hook in the parent process" do
      assert_hook_runs_in_parent(:shutdown, -> {
        Resque.before_fork { @worker.shutdown }
      })
    end

    it "runs before_pause hook in the parent process" do
      assert_hook_runs_in_parent(:before_pause, -> {
        Resque.before_fork { @worker.pause_processing }
      })
    end

    it "runs after_pause hook in the parent process" do
      assert_hook_runs_in_parent(:after_pause, -> {
        Resque.before_fork { @worker.pause_processing; @worker.unpause_processing }
      })
    end

    it "runs worker_exit hook in the parent process" do
      assert_hook_runs_in_parent(:worker_exit)
    end
  end

  it 'retrieving hooks if none have been set' do
    assert_equal [], Resque.before_first_fork
    assert_equal [], Resque.before_fork
    assert_equal [], Resque.after_fork
  end

  it 'it calls before_first_fork once' do
    counter = 0

    Resque.before_first_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(1, counter)
  end

  it 'it calls before_fork before each job' do
    file = Tempfile.new("resque_before_fork") # to share state with forked process

    begin
      File.open(file.path, "w") {|f| f.write(0)}
      Resque.before_fork do
        val = File.read(file).strip.to_i
        File.open(file.path, "w") {|f| f.write(val + 1)}
      end
      2.times { Resque::Job.create(:jobs, CallNotifyJob) }

      val = File.read(file.path).strip.to_i
      assert_equal(0, val)
      @worker.work(0)
      val = File.read(file.path).strip.to_i
      assert_equal(2, val)
    ensure
      file.delete
    end
  end

  it 'it calls after_fork after each job' do
    file = Tempfile.new("resque_after_fork") # to share state with forked process

    begin
      File.open(file.path, "w") {|f| f.write(0)}
      Resque.after_fork do
        val = File.read(file).strip.to_i
        File.open(file.path, "w") {|f| f.write(val + 1)}
      end
      2.times { Resque::Job.create(:jobs, CallNotifyJob) }

      val = File.read(file.path).strip.to_i
      assert_equal(0, val)
      @worker.work(0)
      val = File.read(file.path).strip.to_i
      assert_equal(2, val)
    ensure
      file.delete
    end
  end

  it 'it calls before_first_fork before forking' do
    Resque.before_first_fork { assert(!$called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'it calls before_fork before forking' do
    Resque.before_fork { assert(!$called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'it calls after_fork after forking' do
    Resque.after_fork { assert($called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'it registers multiple before_first_forks' do
    first = false
    second = false

    Resque.before_first_fork { first = true }
    Resque.before_first_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it 'it registers multiple before_forks' do
    # use tempfiles to share state with forked process
    file = Tempfile.new("resque_before_fork_first")
    file2 = Tempfile.new("resque_before_fork_second")

    begin
      File.open(file.path, "w") {|f| f.write(1)}
      File.open(file2.path, "w") {|f| f.write(2)}

      Resque.before_fork do
        val = File.read(file.path).strip.to_i
        File.open(file.path, "w") {|f| f.write(val + 1)}
      end

      Resque.before_fork do
        val = File.read(file2.path).strip.to_i
        File.open(file2.path, "w") {|f| f.write(val + 1)}
      end
      Resque::Job.create(:jobs, CallNotifyJob)

      @worker.work(0)
      val = File.read(file.path).strip.to_i
      val2 = File.read(file2.path).strip.to_i
      assert_equal(val, 2)
      assert_equal(val2, 3)
    ensure
      file.delete
      file2.delete
    end
  end

  it 'it registers multiple after_forks' do
    # use tempfiles to share state with forked process
    file = Tempfile.new("resque_after_fork_first")
    file2 = Tempfile.new("resque_after_fork_second")

    begin
      File.open(file.path, "w") {|f| f.write(1)}
      File.open(file2.path, "w") {|f| f.write(2)}

      Resque.after_fork do
        val = File.read(file.path).strip.to_i
        File.open(file.path, "w") {|f| f.write(val + 1)}
      end

      Resque.after_fork do
        val = File.read(file2.path).strip.to_i
        File.open(file2.path, "w") {|f| f.write(val + 1)}
      end
      Resque::Job.create(:jobs, CallNotifyJob)

      @worker.work(0)
      val = File.read(file.path).strip.to_i
      val2 = File.read(file2.path).strip.to_i
      assert_equal(val, 2)
      assert_equal(val2, 3)
    ensure
      file.delete
      file2.delete
    end
  end
end
