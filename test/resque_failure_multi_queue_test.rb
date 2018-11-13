require 'test_helper'
require 'resque/failure/redis_multi_queue'

describe "Resque::Failure::RedisMultiQueue" do
  let(:bad_string) { [39, 52, 127, 86, 93, 95, 39].map { |c| c.chr }.join }
  let(:exception)  { StandardError.exception(bad_string) }
  let(:worker)     { Resque::Worker.new(:test) }
  let(:queue)      { 'queue' }
  let(:payload)    { { "class" => "Object", "args" => 3 } }

  before do
    Resque::Failure::RedisMultiQueue.clear
    @redis_backend = Resque::Failure::RedisMultiQueue.new(exception, worker, queue, payload)
  end

  it 'cleans up bad strings before saving the failure, in order to prevent errors on the resque UI' do
    # test assumption: the bad string should not be able to round trip though JSON
    @redis_backend.save
    Resque::Failure::RedisMultiQueue.all # should not raise an error
  end

  it '.each iterates correctly (does nothing) for no failures' do
    assert_equal 0, Resque::Failure::RedisMultiQueue.count
    Resque::Failure::RedisMultiQueue.each do |id, item|
      raise "Should not get here"
    end
  end

  it '.each iterates thru a single hash if there is a single failure' do
    @redis_backend.save
    count = Resque::Failure::RedisMultiQueue.count
    assert_equal 1, count
    num_iterations = 0
    queue = Resque::Failure.failure_queue_name('queue')

    Resque::Failure::RedisMultiQueue.each(0, count, queue) do |_id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    assert_equal count, num_iterations
  end

  it '.each iterates thru hashes if there is are multiple failures' do
    @redis_backend.save
    @redis_backend.save
    count = Resque::Failure::RedisMultiQueue.count
    assert_equal 2, count
    num_iterations = 0
    queue = Resque::Failure.failure_queue_name('queue')

    Resque::Failure::RedisMultiQueue.each(0, count, queue) do |_id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    assert_equal count, num_iterations
  end

  it '.each should limit based on the class_name when class_name is specified' do
    num_iterations = 0
    class_one = 'Foo'
    class_two = 'Bar'
    [ class_one,
      class_two,
      class_one,
      class_two,
      class_one,
      class_two
    ].each do |class_name|
      Resque::Failure::RedisMultiQueue.new(exception, worker, queue, payload.merge({ "class" => class_name })).save
    end
    # ensure that there are 6 failed jobs in total as configured
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 6, count
    Resque::Failure::RedisMultiQueue.each 0, 3, queue, class_one do |_id, item|
      num_iterations += 1
      # ensure it iterates only jobs with the specified class name (it was not
      # which cause we only got 1 job with class=Foo since it iterates all the
      # jobs and limit already reached)
      assert_equal class_one, item['payload']['class']
    end
    # ensure only iterates max up to the limit specified
    assert_equal 2, num_iterations
  end

  it '.each should limit normally when class_name is not specified' do
    num_iterations = 0
    class_one = 'Foo'
    class_two = 'Bar'
    [ class_one,
      class_two,
      class_one,
      class_two,
      class_one,
      class_two
    ].each do |class_name|
      Resque::Failure::RedisMultiQueue.new(exception, worker, queue, payload.merge({ "class" => class_name })).save
    end
    # ensure that there are 6 failed jobs in total as configured
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 6, count
    Resque::Failure::RedisMultiQueue.each 0, 5, queue do |id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    # ensure only iterates max up to the limit specified
    assert_equal 5, num_iterations
  end

  it '.each should yield the correct indices when the offset is 0 and the order is descending' do
    50.times { @redis_backend.save }
    queue = Resque::Failure.failure_queue_name('queue')
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 50, count

    offset = 0
    limit = 20
    ids = []
    expected_ids = (offset...limit).to_a.reverse

    Resque::Failure::RedisMultiQueue.each offset, limit, queue do |id, _item|
      ids << id
    end

    assert_equal expected_ids, ids
  end

  it '.each should yield the correct indices when the offset is 0 and the order is ascending' do
    50.times { @redis_backend.save }
    queue = Resque::Failure.failure_queue_name('queue')
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 50, count

    offset = 0
    limit = 20
    ids = []
    expected_ids = (offset...limit).to_a

    Resque::Failure::RedisMultiQueue.each offset, limit, queue, nil, 'asc' do |id, _item|
      ids << id
    end

    assert_equal expected_ids, ids
  end

  it '.each should yield the correct indices when the offset isn\'t 0 and the order is descending' do
    50.times { @redis_backend.save }
    queue = Resque::Failure.failure_queue_name('queue')
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 50, count

    offset = 20
    limit = 20
    ids = []
    expected_ids = (offset...offset + limit).to_a.reverse

    Resque::Failure::RedisMultiQueue.each offset, limit, queue do |id, _item|
      ids << id
    end

    assert_equal expected_ids, ids
  end

  it '.each should yield the correct indices when the offset isn\'t 0 and the order is ascending' do
    50.times { @redis_backend.save }
    queue = Resque::Failure.failure_queue_name('queue')
    count = Resque::Failure::RedisMultiQueue.count
    queue = Resque::Failure.failure_queue_name('queue')
    assert_equal 50, count

    offset = 20
    limit = 20
    ids = []
    expected_ids = (offset...offset + limit).to_a

    Resque::Failure::RedisMultiQueue.each offset, limit, queue, nil, 'asc' do |id, _item|
      ids << id
    end

    assert_equal expected_ids, ids
  end
end
