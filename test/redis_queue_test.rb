require 'test_helper'
require 'resque/queue'

module Resque
  class TestQueue < MiniTest::Unit::TestCase
    class Thing
      attr_reader :inside

      def initialize
        @inside = "x"
      end

      def == other
        super || @inside == other.inside
      end
    end

    def test_sanity
      queue = q
      x = Thing.new
      queue.push x
      assert_equal x, queue.pop
    end

    def test_pop_blocks
      queue1 = q
      queue2 = q

      t = Thread.new { queue1.pop }
      x = Thing.new

      queue2.push x
      assert_equal x, t.join.value
    end

    def test_nonblock_pop
      queue1 = q

      assert_raises ThreadError do
        queue1.pop(true)
      end
    end

    def test_pop_blocks_forever
      queue1 = q
      assert_raises Timeout::Error do
        Timeout.timeout(2) { queue1.pop }
      end
    end

    def test_size
      queue = q
      assert_equal 0, queue.size

      queue << Thing.new
      assert_equal 1, queue.size
    ensure
      queue.pop
    end

    def test_empty?
      queue = q
      assert queue.empty?

      queue << Thing.new
      refute queue.empty?
    ensure
      queue.pop
    end

    def q
      Queue.new 'foo', backend
    end

    def backend
      redis = Redis.new(:host => "127.0.0.1", :port => 9736)
      Redis::Namespace.new :resque, :redis => redis
    end
  end
end
