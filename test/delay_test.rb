require "test_helper"

describe "Resque::DelayProxy disabled" do
  it "should not respond to #delay" do
    assert !Object.respond_to?(:delay)
  end
end

describe "Resque::DelayProxy enabled" do
  let(:redis) { Resque.redis }

  before do
    Resque.inline = true
    Resque.enable_delay_proxy!
    redis.flushall
    redis.set('DelayJob.counter', "0")
    redis.set('DBJob.counter', "0")
    @worker = Resque::Worker.new('*')
  end

  after do
    Resque.inline = false
  end

  it "should exist on faux-DB objects" do
    record = DBJob.new
    record.delay.calculation_method
    assert_equal "3", redis.get('DBJob.counter')
  end

  it "should pass arguments" do
    num = "10"
    DelayJob.delay.method_with_args(num)
    assert_equal num, redis.get('DelayJob.counter')
  end

  it "should respond to #delay" do
    assert Object.respond_to?(:delay)
  end

  it "should exist on classes" do
    DelayJob.delay.a_class_method
    assert_equal "2", redis.get('DelayJob.counter')
  end

  it "should raise when unsupported object is used" do
    record = UnsupportedDelayJob.new
    assert_raises RuntimeError do
      record.delay.work
    end
  end
end
