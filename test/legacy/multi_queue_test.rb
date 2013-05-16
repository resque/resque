require "test_helper"

describe "Resque::MultiQueue" do
  let(:redis) { Resque.backend.store }
  let(:coder) { Resque::JsonCoder.new }

  before do
    redis.flushall
  end

  it "poll times out and returns nil" do
    foo   = Resque::Queue.new 'foo', redis
    bar   = Resque::Queue.new 'bar', redis
    queue = Resque::MultiQueue.new([foo, bar], redis)
    assert_nil queue.poll(1)
  end

  it "poll is a no-op when queues are empty" do
    queue = Resque::MultiQueue.new([], redis)
    assert_nil queue.poll(1)
  end

  it "multi-q blocks on pop" do
    timeout_count = 0
    10.times do
      foo   = Resque::Queue.new 'foo', redis, coder
      bar   = Resque::Queue.new 'bar', redis, coder
      queue = Resque::MultiQueue.new([foo, bar], redis)
      t     = Thread.new { queue.pop }

      job = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }
      bar << job

      begin
        timeout(20) do
          assert_equal [bar, job], t.join.value
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

  it "blocking pop processes queues in the order given" do
    foo    = Resque::Queue.new 'foo', redis, coder
    bar    = Resque::Queue.new 'bar', redis, coder
    baz    = Resque::Queue.new 'baz', redis, coder
    queues = [foo, bar, baz]
    queue  = Resque::MultiQueue.new(queues, redis)
    job    = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }

    queues.each {|q| q << job }

    processed_queues = queues.map do
      queue.pop[0]
    end

    assert_equal processed_queues, queues
  end

  it "nonblocking pop processes queues in the order given" do
    foo    = Resque::Queue.new 'foo', redis, coder
    bar    = Resque::Queue.new 'bar', redis, coder
    baz    = Resque::Queue.new 'baz', redis, coder
    queues = [foo, bar, baz]
    queue  = Resque::MultiQueue.new(queues, redis)
    job    = { 'class' => 'GoodJob', 'args' => [35, 'tar'] }

    queues.each {|q| q << job }

    processed_queues = queues.map do
      queue.pop[0]
    end

    assert_equal processed_queues, queues
  end

  it "blocking pop is a no-op if queues are empty" do
    queue = Resque::MultiQueue.new([], redis)
    assert_raises Timeout::Error do
      Timeout.timeout(2) { queue.pop }
    end
  end
end
