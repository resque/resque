require 'failure/failure_backend_test'
require 'resque/failure/redis_multi_queue'
require 'mock_redis'

describe Resque::Failure::RedisMultiQueue do
  before :each do
    Resque.redis = MockRedis.new :host => "localhost", :port => 9736, :db => 0
    Resque::Failure.backend = Resque::Failure::RedisMultiQueue

    queue = :jobs
    # make two failures 
    data = Resque.encode({:failure_data=>:blahblah})
    2.times { Resque.redis.rpush(Resque::Failure.failure_queue_name(queue), data) }
  end
  it_behaves_like 'A Failure Backend'

  it 'saves' do

  end
end
