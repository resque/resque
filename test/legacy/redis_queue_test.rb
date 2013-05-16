require 'test_helper'
require 'resque/queue'

describe "Resque::Queue" do
  class Thing
    attr_reader :inside

    def initialize
      @inside = "x"
    end

    def == other
      super || @inside == other.inside
    end
  end

  before do
    Resque.backend.store.flushall
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
    timeout_count = 0
    10.times do
      queue1 = q
      queue2 = q

      t = Thread.new { queue1.pop }
      x = Thing.new

      queue2.push x

      begin
        timeout(20) do
          assert_equal x, t.join.value
        end
      rescue Timeout::Error => e
        timeout_count += 1
        puts e.inspect
        puts e.backtrace.join("\n")
      end
    end
    puts timeout_count.inspect
    assert timeout_count < 10, "Should have passed at least once. Failed #{timeout_count} times."
  end

  it "nonblocking pop works" do
    queue1 = q
    x      = Thing.new

    queue1 << x
    assert_equal x, queue1.pop
  end

  it "nonblocking pop doesn't block" do
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

  it "registers itself with Resque" do
    q

    assert_equal ["foo"], Resque.queues
  end

  it "cleans up after itself when destroyed" do
    queue = q
    queue << Thing.new
    q.destroy

    assert_equal [], Resque.queues
    assert !Resque.backend.store.exists(queue.redis_name)
  end

  it "returns false if a queue is not destroyed" do
    assert !q.destroyed?
  end

  it "returns true if a queue is destroyed" do
    queue1 = q
    queue1.destroy
    assert queue1.destroyed?
  end

  it "can't push to queue after destroying it" do
    queue1 = q
    x      = Thing.new
    queue1 << x
    queue1.destroy

    assert_raises Resque::QueueDestroyed do
      queue1 << x
    end
  end

  def q
    Resque::Queue.new 'foo', Resque.backend.store
  end
end
