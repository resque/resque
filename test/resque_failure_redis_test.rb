require 'test_helper'
require 'resque/failure/redis'

describe "Resque::Failure::Redis" do
  let(:bad_string) { [39, 52, 127, 86, 93, 95, 39].map { |c| c.chr }.join }
  let(:exception)  { StandardError.exception(bad_string) }
  let(:worker)     { Resque::Worker.new(:test) }
  let(:queue)      { "queue" }
  let(:payload)    { { "class" => "Object", "args" => 3 } }

  before do
    Resque::Failure::Redis.clear
    @redis_backend = Resque::Failure::Redis.new(exception, worker, queue, payload)
  end

  it 'cleans up bad strings before saving the failure, in order to prevent errors on the resque UI' do
    # test assumption: the bad string should not be able to round trip though JSON
    @redis_backend.save
    Resque::Failure::Redis.all # should not raise an error
  end

  it '.each iterates correctly (does nothing) for no failures' do
    assert_equal 0, Resque::Failure::Redis.count
    Resque::Failure::Redis.each do |id, item|
      raise "Should not get here"
    end
  end

  it '.each iterates thru a single hash if there is a single failure' do
    @redis_backend.save
    assert_equal 1, Resque::Failure::Redis.count
    num_iterations = 0
    Resque::Failure::Redis.each do |id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    assert_equal 1, num_iterations
  end

  it '.each iterates thru hashes if there is are multiple failures' do
    @redis_backend.save
    @redis_backend.save
    num_iterations = 0
    assert_equal 2, Resque::Failure::Redis.count
    Resque::Failure::Redis.each do |id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    assert_equal 2, num_iterations
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
      Resque::Failure::Redis.new(exception, worker, queue, payload.merge({ "class" => class_name })).save
    end
    # ensure that there are 6 failed jobs in total as configured
    assert_equal 6, Resque::Failure::Redis.count
    Resque::Failure::Redis.each 0, 2, nil, class_one do |id, item|
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
      Resque::Failure::Redis.new(exception, worker, queue, payload.merge({ "class" => class_name })).save
    end
    # ensure that there are 6 failed jobs in total as configured
    assert_equal 6, Resque::Failure::Redis.count
    Resque::Failure::Redis.each 0, 5 do |id, item|
      num_iterations += 1
      assert_equal Hash, item.class
    end
    # ensure only iterates max up to the limit specified
    assert_equal 5, num_iterations
  end

end
