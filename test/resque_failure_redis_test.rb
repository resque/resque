require 'test_helper'
require 'resque/failure/redis'

describe "Resque::Failure::Redis" do
  before do
    Resque::Failure::Redis.clear
    @bad_string    = [39, 52, 127, 86, 93, 95, 39].map { |c| c.chr }.join
    exception      = StandardError.exception(@bad_string)
    worker         = Resque::Worker.new(:test)
    queue          = "queue"
    payload        = { "class" => Object, "args" => 3 }
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

end
