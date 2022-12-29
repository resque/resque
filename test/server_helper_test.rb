require 'test_helper'
require 'resque/server_helper'

describe 'Resque::ServerHelper' do
  include Resque::ServerHelper

  def exists?(key)
    if Gem::Version.new(Redis::VERSION) >= Gem::Version.new('4.2.0')
      Resque.redis.exists?(key)
    else
      Resque.redis.exists(key)
    end
  end

  describe 'redis_get_size' do
    describe 'when the data type is none' do
      it 'returns 0' do
        refute exists?('none')
        assert_equal 0, redis_get_size('none')
      end
    end

    describe 'when the data type is hash' do
      it 'returns the number of fields contained in the hash' do
        Resque.redis.hset('hash','f1', 'v1')
        Resque.redis.hset('hash','f2', 'v2')
        assert_equal 2, redis_get_size('hash')
      end
    end

    describe 'when the data type is list' do
      it 'returns the length of the list' do
        Resque.redis.rpush('list', 'v1')
        Resque.redis.rpush('list', 'v2')
        assert_equal 2, redis_get_size('list')
      end
    end

    describe 'when the data type is set' do
      it 'returns the number of elements of the set' do
        Resque.redis.sadd('set', ['v1', 'v2'])
        assert_equal 2, redis_get_size('set')
      end
    end

    describe 'when the data type is string' do
      it 'returns the length of the string' do
        Resque.redis.set('string', 'test value')
        assert_equal 'test value'.length, redis_get_size('string')
      end
    end

    describe 'when the data type is zset' do
      it 'returns the number of elements of the zset' do
        Resque.redis.zadd('zset', 1, 'v1')
        Resque.redis.zadd('zset', 2, 'v2')
        assert_equal 2, redis_get_size('zset')
      end
    end
  end

  describe 'redis_get_value_as_array' do
    describe 'when the data type is none' do
      it 'returns an empty array' do
        refute exists?('none')
        assert_equal [], redis_get_value_as_array('none')
      end
    end

    describe 'when the data type is hash' do
      it 'returns an array of 20 elements counting from `start`' do
        Resque.redis.hset('hash','f1', 'v1')
        Resque.redis.hset('hash','f2', 'v2')
        assert_equal [['f1', 'v1'], ['f2', 'v2']], redis_get_value_as_array('hash')
      end
    end

    describe 'when the data type is list' do
      it 'returns an array of 20 elements counting from `start`' do
        Resque.redis.rpush('list', 'v1')
        Resque.redis.rpush('list', 'v2')
        assert_equal ['v1', 'v2'], redis_get_value_as_array('list')
      end
    end

    describe 'when the data type is set' do
      it 'returns an array of 20 elements counting from `start`' do
        Resque.redis.sadd('set', ['v1', 'v2'])
        assert_equal ['v1', 'v2'], redis_get_value_as_array('set').sort
      end
    end

    describe 'when the data type is string' do
      it 'returns an array of value' do
        Resque.redis.set('string', 'test value')
        assert_equal ['test value'], redis_get_value_as_array('string')
      end
    end

    describe 'when the data type is zset' do
      it 'returns an array of 20 elements counting from `start`' do
        Resque.redis.zadd('zset', 1, 'v1')
        Resque.redis.zadd('zset', 2, 'v2')
        assert_equal ['v1', 'v2'], redis_get_value_as_array('zset')
      end
    end
  end
end
