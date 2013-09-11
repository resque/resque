require 'test_helper'
require 'resque/failure'

describe Resque::Failure do
  before do
    # defaulting to multi queue based on the expressed desire to move away from
    # a single failure queue system
    Resque::Failure.backend = Resque::Failure::RedisMultiQueue
  end

  after do
    Resque::Failure.backend = nil
    Resque.backend.store.flushall
  end

  describe '::create' do
    it 'initializes and creates a new Failure instance with the given options' do
      failure = save_failure :queue => :queue1
      result = Resque.backend.store.lindex(:queue1_failed, 0)
      assert_match failure.queue.to_s, result
      assert_instance_of Resque::Failure, failure
    end
  end

  describe '::failure_queue_name' do
    it 'returns the failure queue name given a normal queue name' do
      assert_equal 'foo_failed', Resque::Failure.failure_queue_name('foo')
    end
  end

  describe '::job_queue_name' do
    it 'returns the normal queue name given a failure queue name' do
      assert_equal 'foo', Resque::Failure.job_queue_name('foo_failed')
    end
  end

  describe '::list_range' do
    it 'returns instances of the Resque::Failure class' do
      save_failure
      result = Resque::Failure.list_range :queue1_failed
      assert_instance_of Resque::Failure, result
    end
  end

  describe '::full_list' do
    it 'returns instances of the Resque::Failure class' do
      save_failure
      result = Resque::Failure.full_list :queue1_failed
      assert_instance_of Resque::Failure, result.first
    end
  end

  describe '#save' do
    it 'delegates saving the failure instance to the backend' do
      failure = Resque::Failure.new(
        :raw_exception => Exception.new,
        :queue => :queue1,
        :payload => {}
      )

      Resque::Failure.backend = MiniTest::Mock.new
      Resque::Failure.backend.expect :save, 1, [failure]
      failure.save

      Resque::Failure.backend.verify
    end
  end

  describe '#data' do
    it 'returns a hash representing the failure instance to be persisted to Redis' do
      failure = save_failure
      data = failure.data
      assert_instance_of String, data[:failed_at]
      assert_equal({ 'class' => 'some_class', 'args' => 'some_args' }, data[:payload])
      assert_equal 'Exception', data[:exception]
      assert_equal 'job blew up', data[:error]
      assert_equal [], data[:backtrace]
      assert_equal 'some_worker', data[:worker]
      assert_equal 'queue1', data[:queue].to_s
      assert_nil data[:retried_at]
    end
  end

  describe '#failed_at' do
    it 'returns the time the failure was retried at' do
      Time.stub :now, Time.at(0) do
        failure = save_failure
        assert_equal Time.at(0), Time.parse(failure.failed_at)
      end
    end
  end

  describe '#exception' do
    it 'returns the class name of the exception' do
      failure = save_failure
      assert_equal 'Exception', failure.exception
    end
  end

  describe '#error' do
    it 'returns the error message from the exception' do
      failure = save_failure
      assert_equal 'job blew up', failure.error
    end
  end

  describe '#backtrace' do
    it 'returns the filtered backtrace' do
      backtrace = ['show', '/lib/resque/job.rb', 'hide']
      exception = Exception.new
      exception.stub :backtrace, backtrace do
        failure = save_failure :raw_exception => exception
        assert_equal ['show'], failure.backtrace
      end
    end
  end

  describe '#failed_queue' do
    it 'returns the name of the failure queue the instance was retrieved from' do
      failure = save_failure
      assert_equal 'queue1_failed', failure.failed_queue
    end
  end

  describe '#class_name' do
    it 'returns the original job class name' do
      failure = save_failure
      assert_equal 'some_class', failure.class_name
    end
  end

  describe '#args' do
    it 'returns the args from the original job' do
      failure = save_failure
      assert_equal 'some_args', failure.args
    end
  end

  describe '#retry' do
    it 'retries the failed job' do
      # surely theres a better way to test this?
      Resque::Failure::Job = MiniTest::Mock.new
      Resque::Failure::Job.expect :create, :return, [:queue1, 'some_class', 'some_args']
      failure = save_failure
      failure.retry
      Resque::Failure::Job.verify
      Resque::Failure.send(:remove_const, :Job)
    end

    it 'sets the retried_at time' do
      Resque::Job.stub :create, :return do
        failure = save_failure
        Time.stub :now, Time.at(0) do
          failure.retry
          assert_equal Time.at(0), Time.parse(failure.retried_at)
        end
      end
    end

    it 'retries the job on a different queue if provided' do
      # surely theres a better way to test this?
      Resque::Failure::Job = MiniTest::Mock.new
      Resque::Failure::Job.expect :create, :return, [:another_queue, 'some_class', 'some_args']
      failure = save_failure
      failure.retry(:another_queue)
      Resque::Failure::Job.verify
      Resque::Failure.send(:remove_const, :Job)
    end
  end

  describe '#destroy' do
    it 'deletes the failure record from Redis' do
      failure = save_failure
      failure.destroy
      assert_nil Resque::Failure.all[:queue1_failed].first
    end

    it 'freezes the failure object' do
      failure = save_failure
      failure.destroy
      assert failure.frozen?
    end
  end

  describe '#clear' do
    it 'clears the failure record in Redis (but not delete it)' do
      failure = save_failure
      failure.clear
      assert_equal [''], Resque.backend.store.lrange('queue1_failed', 0, -1)
    end
  end

  private

  def save_failure(options = {})
    options = {
      :raw_exception => Exception.new('job blew up'),
      :queue => :queue1,
      :worker => 'some_worker',
      :payload => { 'class' => 'some_class', 'args' => 'some_args' }
    }.merge(options)
    Resque::Failure.create(options)
  end
end
