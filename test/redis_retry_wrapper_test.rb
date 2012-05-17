require 'test_helper'

describe "Resque::RedisRetryWrapper" do
  include Test::Unit::Assertions
  
  before do
    @redis_wrapper = Resque::RedisRetryWrapper.new(Resque.redis)
    Resque::RedisRetryWrapper.any_instance.stubs(:sleep_seconds).returns(0) # retry faster to speed up the tests
  end
  
  it 'sends commands to Redis' do
    Redis.any_instance.expects(:hello).with(nil)
    @redis_wrapper.hello
  end

  it 'retries commands upon receiving connection errors' do
    Redis::Client.any_instance.expects(:connected?).at_least(3).returns(false)
    Redis::Client.any_instance.expects(:establish_connection).at_least(3).raises(Errno::EAGAIN)
    
    @redis_wrapper.lpop('retry_wrapper_test') rescue true
  end
  
  # this is our block test. a stubbed block test doesn't appear to be possible in mocha right now
  # http://stackoverflow.com/questions/3252046/mock-methods-that-receives-a-block-as-parameter
  it 'runs multi' do
    @redis_wrapper.multi do
      Resque.redis.set "foo", "bar"
      Resque.redis.incr "baz"
    end
    
    assert_equal "bar", Resque.redis.get("foo")
    assert_equal "1", Resque.redis.get("baz")
  end
end
