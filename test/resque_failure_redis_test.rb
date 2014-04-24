require 'test_helper'
require 'resque/failure/redis'

context "Resque::Failure::Redis" do
  setup do
    @bad_string    = [39, 52, 127, 86, 93, 95, 39].map { |c| c.chr }.join
    exception      = StandardError.exception(@bad_string)
    worker         = Resque::Worker.new(:test)
    queue          = "queue"
    payload        = { "class" => Object, "args" => 3 }
    @redis_backend = Resque::Failure::Redis.new(exception, worker, queue, payload)
  end

  test 'cleans up bad strings before saving the failure, in order to prevent errors on the resque UI' do
    # test assumption: the bad string should not be able to round trip though JSON
    @redis_backend.save
    Resque::Failure::Redis.all # should not raise an error
  end
end

describe ".each" do

  context 'order ASC' do
    setup do
      exception      = StandardError.exception("error")
      worker         = Resque::Worker.new(:test)
      queue          = "queue"
      payload        = { "class" => Object, "args" => 3 }
      5.times do
        Resque::Failure::Redis.new(exception, worker, queue, payload).save
      end
    end

    test "should iterate over the failed tasks with ids in order" do
      ids = []
      Resque::Failure::Redis.each(0, 3, :failed, nil, 'asc') do |id, _|
        ids << id
      end
      assert_equal([0,1,2], ids)
    end
  end

  context 'order desc' do
    test "should iterate over the failed tasks with ids in reverse order" do
      ids = []
      Resque::Failure::Redis.each(2, 3, :failed, nil, 'desc') do |id, _|
        ids << id
      end
      assert_equal([4,3,2], ids)
    end
  end
end
