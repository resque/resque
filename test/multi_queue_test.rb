require "test_helper"

describe "Resque::MulitQueue" do
  let(:redis) { Resque.redis }
  let(:pool)  { Resque.pool }
  let(:coder) { Resque::MultiJsonCoder.new }

  it "poll times out and returns nil" do
    foo   = Resque::Queue.new 'foo', pool
    bar   = Resque::Queue.new 'bar', pool
    queue = Resque::MultiQueue.new([foo, bar], pool)
    assert_nil queue.poll(1)
  end

  it "blocks on pop" do
    foo   = Resque::Queue.new 'foo', pool, coder
    bar   = Resque::Queue.new 'bar', pool, coder
    queue = Resque::MultiQueue.new([foo, bar], pool)
    t     = Thread.new { queue.pop }

    job = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }
    bar << job

    assert_equal [bar, job], t.join.value
  end

  it "nonblocking pop works" do
    foo   = Resque::Queue.new 'foo', pool, coder
    bar   = Resque::Queue.new 'bar', pool, coder
    queue = Resque::MultiQueue.new([foo, bar], pool)

    job = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }
    bar << job

    assert_equal [bar, job], queue.pop(true)
  end

  it "nonblocking pop doesn't block" do
    foo   = Resque::Queue.new 'foo', pool, coder
    bar   = Resque::Queue.new 'bar', pool, coder
    queue = Resque::MultiQueue.new([foo, bar], pool)

    assert_raises ThreadError do
      queue.pop(true)
    end
  end

  it "blocks forever on pop" do
    foo   = Resque::Queue.new 'foo', pool, coder
    bar   = Resque::Queue.new 'bar', pool, coder
    queue = Resque::MultiQueue.new([foo, bar], pool)
    assert_raises Timeout::Error do
      Timeout::timeout(2) { queue.pop }
    end
  end

  it "blocking pop processes queues in the order given" do
    foo    = Resque::Queue.new 'foo', pool, coder
    bar    = Resque::Queue.new 'bar', pool, coder
    baz    = Resque::Queue.new 'baz', pool, coder
    queues = [foo, bar, baz]
    queue  = Resque::MultiQueue.new(queues, pool)
    job    = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }

    queues.each {|q| q << job }

    processed_queues = queues.map do
      q, j = queue.pop
      q
    end

    assert_equal processed_queues, queues
  end

  it "nonblocking pop processes queues in the order given" do
    foo    = Resque::Queue.new 'foo', pool, coder
    bar    = Resque::Queue.new 'bar', pool, coder
    baz    = Resque::Queue.new 'baz', pool, coder
    queues = [foo, bar, baz]
    queue  = Resque::MultiQueue.new(queues, pool)
    job    = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }

    queues.each {|q| q << job }

    processed_queues = queues.map do
      q, j = queue.pop(true)
      q
    end

    assert_equal processed_queues, queues
  end
end
