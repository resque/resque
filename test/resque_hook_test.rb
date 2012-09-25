require 'test_helper'

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
    counter = 0

    Resque.after_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(2, counter)
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

  it 'it registeres multiple before_first_forks' do
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

  it 'it registers multiple after_forks' do
    first = false
    second = false

    Resque.after_fork { first = true }
    Resque.after_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it "will call before_pause before it is paused" do
    before_pause_called = false
    captured_worker = nil

    Resque.before_pause do |worker|
      before_pause_called = true
      captured_worker = worker
    end

    @worker.pause_processing

    assert !before_pause_called

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert before_pause_called
    assert_equal @worker, captured_worker
  end

  it "will call after_pause after it is paused" do
    after_pause_called = false
    captured_worker = nil

    Resque.after_pause do |worker|
      after_pause_called = true
      captured_worker = worker
    end

    @worker.pause_processing

    assert !after_pause_called

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert after_pause_called
    assert_equal @worker, captured_worker
  end

  it 'it registers multiple before_pauses' do
    first_pause = false
    first_worker = nil

    second_pause = false
    second_worker = nil

    Resque.before_pause do |worker|
      first_pause = true
      first_worker = worker
    end

    Resque.before_pause do |worker|
      second_pause = true
      second_worker = worker
    end

    @worker.pause_processing

    assert (!first_pause && !second_pause)

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert first_pause && second_pause
    assert_equal @worker, first_worker
    assert_equal @worker, second_worker
  end

  it 'it registers multiple after_pauses' do
    first_pause = false
    first_worker = nil

    second_pause = false
    second_worker = nil

    Resque.after_pause do |worker|
      first_pause = true
      first_worker = worker
    end

    Resque.after_pause do |worker|
      second_pause = true
      second_worker = worker
    end

    @worker.pause_processing

    assert (!first_pause && !second_pause)

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert first_pause && second_pause
    assert_equal @worker, first_worker
    assert_equal @worker, second_worker
  end
end
