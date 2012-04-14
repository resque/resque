require "test_helper"

describe "Resque::MulitQueue" do
  let(:redis) { Resque.redis }
  let(:coder) { Resque::MultiJsonCoder.new }

  before do
    redis.flushall
  end

  it "blocks on pop" do
    foo   = Resque::Queue.new 'foo', redis, coder
    bar   = Resque::Queue.new 'bar', redis, coder
    queue = Resque::MultiQueue.new([foo, bar], redis)
    t     = Thread.new { queue.pop }

    job = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }
    bar << job

    assert_equal [bar, job], t.join.value
  end

  it "nonblocking pop works" do
    foo   = Resque::Queue.new 'foo', redis, coder
    bar   = Resque::Queue.new 'bar', redis, coder
    queue = Resque::MultiQueue.new([foo, bar], redis)

    job = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }
    bar << job

    assert_equal [bar, job], queue.pop(true)
  end

  it "nonblocking pop doesn't block" do
    foo   = Resque::Queue.new 'foo', redis, coder
    bar   = Resque::Queue.new 'bar', redis, coder
    queue = Resque::MultiQueue.new([foo, bar], redis)

    assert_raises ThreadError do
      queue.pop(true)
    end
  end

  it "blocks forever on pop" do
    foo   = Resque::Queue.new 'foo', redis, coder
    bar   = Resque::Queue.new 'bar', redis, coder
    queue = Resque::MultiQueue.new([foo, bar], redis)
    assert_raises Timeout::Error do
      Timeout::timeout(2) { queue.pop }
    end
  end
end
