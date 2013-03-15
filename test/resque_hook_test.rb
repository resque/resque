require 'test_helper'
require 'tempfile'

describe "Resque Hooks" do
  before do
    Resque.redis.flushall

    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil

    @worker = Resque::Worker.new(:jobs)

    $called = false

    class CallNotifyJob
      def self.perform
        $called = true
      end
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
    counter = 0

    Resque.before_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(2, counter)
  end

  it 'it calls after_fork after each job' do
    skip("TRAAAVIS!!!!") if RUBY_VERSION == "1.8.7"
    # We have to stub out will_fork? to return true, which is going to cause an actual fork(). As such, the
    # exit!(true) will be called in Worker#work; to share state, use a tempfile
    file = Tempfile.new("resque_after_fork")

    begin
      File.open(file.path, "w") {|f| f.write(0)}
      Resque.after_fork do
        val = File.read(file).strip.to_i
        File.open(file.path, "w") {|f| f.write(val + 1)}
      end
      2.times { Resque::Job.create(:jobs, CallNotifyJob) }

      val = File.read(file.path).strip.to_i
      assert_equal(0, val)
      @worker.stubs(:will_fork?).returns(true)
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
    first = false
    second = false

    Resque.before_fork { first = true }
    Resque.before_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it 'flattens hooks on assignment' do
    first = false
    second = false
    Resque.before_fork = [Proc.new { first = true }, Proc.new { second = true }]
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it 'it registers multiple after_forks' do
    # We have to stub out will_fork? to return true, which is going to cause an actual fork(). As such, the
    # exit!(true) will be called in Worker#work; to share state, use a tempfile
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

      @worker.stubs(:will_fork?).returns(true)
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
