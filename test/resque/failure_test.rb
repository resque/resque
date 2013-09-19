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
      result = Resque.backend.store.hget(:queue1_failed, failure.redis_id)
      assert_match failure.queue.to_s, result
      assert_match failure.redis_id.to_s, result
      assert_instance_of Resque::Failure, failure
    end
  end

  describe '::next_failure_id' do
    it 'returns the next id from the :next_failure_id Redis counter' do
      assert_equal 1, Resque::Failure.next_failure_id
      assert_equal 2, Resque::Failure.next_failure_id
      assert_equal 3, Resque::Failure.next_failure_id
    end
  end

  describe '::failure_queue_name' do
    it 'returns the failure queue name given a normal queue name' do
      assert_equal 'foo_failed', Resque::Failure.failure_queue_name('foo')
    end
  end

  describe '::failure_ids_queue_name' do
    it 'returns the failure ids queue name given a failure queue name' do
      assert_equal 'foo_failed_ids', Resque::Failure.failure_ids_queue_name('foo_failed')
    end
  end

  describe '::job_queue_name' do
    it 'returns the normal queue name given a failure queue name' do
      assert_equal 'foo', Resque::Failure.job_queue_name('foo_failed')
    end
  end

  describe '::list_ids_range' do
    it 'returns the ids for failures from the given queue with the given start/offset' do
      failures = 4.times.map { save_failure }
      target_ids = failures[1, 2].map { |f| f.redis_id.to_s }
      results = Resque::Failure.list_ids_range :queue1_failed_ids, 1, 2
      assert_equal target_ids, results
    end
  end

  describe '::hash_find' do
    it 'returns an array of failures with the given ids from the given queue' do
      failures = 3.times.map { save_failure }
      target_ids = failures.take(2).map(&:redis_id)
      results = Resque::Failure.hash_find *target_ids, :queue1_failed
      assert_instance_of Resque::Failure, results.first
      assert_equal 2, results.size
      assert_equal target_ids, results.map(&:redis_id)
    end

    it 'returns an array with one failure with the given id from the given queue' do
      failure = save_failure
      results = Resque::Failure.hash_find failure.redis_id, :queue1_failed
      assert_equal 1, results.size
      assert_instance_of Resque::Failure, results.first
    end

    it 'returns an empty array when the given id does not exist in the queue' do
      failure = save_failure
      results = Resque::Failure.hash_find (failure.redis_id + 1), :queue1_failed
      assert_empty results
    end
  end

  describe '::full_hash' do
    it 'returns an array of failures from the given queue' do
      failures = 3.times.map { save_failure }
      results = Resque::Failure.full_hash :queue1_failed
      assert_instance_of Resque::Failure, results.first
      assert_equal 3, results.size
      assert_equal failures.map(&:redis_id), results.map(&:redis_id).sort
    end

    it 'returns an empty array when the given queue does not exist' do
      results = Resque::Failure.full_hash :foo_bar_baz
      assert_empty results
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

    it 'assigns a redis_id to the failure' do
      failure_one = save_failure
      failure_two = save_failure
      assert_equal 1, failure_one.redis_id
      assert_equal 2, failure_two.redis_id
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

  describe '#failed_id_queue' do
    it 'returns the name of the failure id list that is storing the failure id' do
      failure = save_failure
      assert_equal 'queue1_failed_ids', failure.failed_id_queue
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
      refute_empty Resque::Failure.all[:queue1_failed]
      failure.destroy
      assert_empty Resque::Failure.all[:queue1_failed]
    end

    it 'freezes the failure object' do
      failure = save_failure
      failure.destroy
      assert failure.frozen?
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
