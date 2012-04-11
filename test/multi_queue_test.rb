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

    job = Resque::Job.new(:bar, :class => 'GoodJob')
    bar << job
    assert_equal coder.decode(job.to_json), t.join.value
  end

  it "nonblocking pop works" do
    foo   = Resque::Queue.new 'foo', redis, coder
    bar   = Resque::Queue.new 'bar', redis, coder
    queue = Resque::MultiQueue.new([foo, bar], redis)

    job = Resque::Job.new(:bar, :class => 'GoodJob')
    bar << job
    assert_equal coder.decode(job.to_json), queue.pop(true)
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
