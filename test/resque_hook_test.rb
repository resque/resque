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

  it 'retrieving hooks if none have been set' do
    assert_equal [], Resque.before_first_fork
  end

  it 'it calls before_first_fork once' do
    counter = 0

    Resque.before_first_fork { counter += 1 }
    2.times { Resque::Job.create(:jobs, CallNotifyJob) }

    assert_equal(0, counter)
    @worker.work(0)
    assert_equal(1, counter)
  end

  it 'it calls before_first_fork before forking' do
    Resque.before_first_fork { assert(!$called) }

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
end
