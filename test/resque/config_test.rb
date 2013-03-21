require 'test_helper'
require 'minitest/mock'

describe Resque::Config do
  it "defaults" do
    defaults = {
      :deamon => false,
      :count => 5,
      :failure_backend => "redis",
      :fork_per_job => true,
      :interval => 5,
      :pid => nil,
      :queues => "*",
      :timeout => 4.0,
      :require => nil
    }

    assert_equal defaults, Resque::Config.new.options
  end

  it "return config var from ENV if set" do
    ENV["QUEUES"] = "high,failure"
    config = Resque::Config.new
    assert_equal config.queues, ["high", "failure"]
    ENV.delete("QUEUES")
  end

  it "return config var from file (should overwrite ENV)" do
    ENV["QUEUES"] = "low,archive"
    config = Resque::Config.new({ "queue" => "low,archive" })
    assert_equal config.queues, ["low", "archive"]
    ENV.delete("QUEUES")
  end

  it "method missing" do
    config = Resque::Config.new(:foo => "bar")
    assert_equal config.options[:foo], "bar"
    assert_equal config.foo, "bar"
  end

  it "interval & time should be floats" do
    config = Resque::Config.new(:interval => "1", :timeout => "2")

    assert_equal config.interval, 1.0
    assert_equal config.timeout, 2.0
  end
end
