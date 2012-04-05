require 'test_helper'
require 'resque/queue'

describe "Resque::Queue" do
  include Test::Unit::Assertions

  class Thing
    attr_reader :inside

    def initialize
      @inside = "x"
    end

    def == other
      super || @inside == other.inside
    end
  end

  it "generates a redis_name" do
    assert_equal "queue:foo", q.redis_name
  end

  it "acts sanely" do
    queue = q
    x = Thing.new
    queue.push x
    assert_equal x, queue.pop
  end

  it "blocks on pop" do
    queue1 = q
    queue2 = q

    t = Thread.new { queue1.pop }
    x = Thing.new

    queue2.push x
    assert_equal x, t.join.value
  end

  it "nonblocking pop works" do
    queue1 = q

    assert_raises ThreadError do
      queue1.pop(true)
    end
  end

  it "blocks forever on pop" do
    queue1 = q
    assert_raises Timeout::Error do
      Timeout.timeout(2) { queue1.pop }
    end
  end

  it "#size" do
    queue = q

    begin
      assert_equal 0, queue.size

      queue << Thing.new
      assert_equal 1, queue.size
    ensure
      queue.pop
    end
  end

  it "#empty?" do
    queue = q

    begin
      assert queue.empty?

      queue << Thing.new
      refute queue.empty?
    ensure
      queue.pop
    end
  end

  def q
    Resque::Queue.new 'foo', backend
  end

  def backend
    Redis::Namespace.new :resque, :redis => Resque.redis
  end
end
