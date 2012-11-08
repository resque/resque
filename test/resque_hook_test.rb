require 'test_helper'

describe "Resque Hooks" do
  before do
    Resque.redis.flushall

    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil
    Resque.before_perform = nil
    Resque.after_perform = nil

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
    assert_equal [], Resque.before_perform
    assert_equal [], Resque.after_perform
  end

  it 'calls before_first_fork once' do
    counter = 0

    Resque.before_first_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(1, counter)
  end

  it 'calls before_fork before each job' do
    counter = 0

    Resque.before_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(@worker.will_fork? ? 2 : 0, counter)
  end

  it 'calls before_perform before each job' do
    counter = 0

    Resque.before_perform { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(2, counter)
  end

  it 'calls after_fork after each job if forking' do
    counter = 0

    Resque.after_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(@worker.will_fork? ? 2 : 0, counter)
  end

  it 'calls after_perform after each job' do
    counter = 0

    Resque.after_perform { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(2, counter)
  end

  it 'calls before_first_fork before forking' do
    Resque.before_first_fork { assert(!$called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'calls before_fork before forking' do
    Resque.before_fork { assert(!$called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'calls after_fork after forking' do
    Resque.after_fork { assert($called) }

    Resque::Job.create(:jobs, CallNotifyJob)
    @worker.work(0)
  end

  it 'registeres multiple before_first_forks' do
    first = false
    second = false

    Resque.before_first_fork { first = true }
    Resque.before_first_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it 'registers multiple before_forks' do
    first = false
    second = false

    Resque.before_fork { first = true }
    Resque.before_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)

    if @worker.will_fork?
      assert(first && second)
    else
      assert(!first && !second)
    end
  end

  it 'registers multiple after_forks' do
    first = false
    second = false

    Resque.after_fork { first = true }
    Resque.after_fork { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)

    if @worker.will_fork?
      assert(first && second)
    else
      assert(!first && !second)
    end
  end

  it 'registers multiple before_pause hooks' do
    first = false
    second = false

    Resque.before_pause { first = true }
    Resque.before_pause { second = true }

    @worker.pause_processing

    assert(!first && !second)

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }
    @worker.work(0)
    t.join

    assert(first && second)
  end

  it 'registers multiple after_pause hooks' do
    first = false
    second = false

    Resque.after_pause { first = true }
    Resque.after_pause { second = true }

    @worker.pause_processing

    assert(!first && !second)

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }
    @worker.work(0)
    t.join

    assert(first && second)
  end

  it 'registers multiple before_perform' do
    first = false
    second = false

    Resque.before_perform { first = true }
    Resque.before_perform { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

  it 'registers multiple after_perform' do
    first = false
    second = false

    Resque.after_perform { first = true }
    Resque.after_perform { second = true }
    Resque::Job.create(:jobs, CallNotifyJob)

    assert(!first && !second)
    @worker.work(0)
    assert(first && second)
  end

end
