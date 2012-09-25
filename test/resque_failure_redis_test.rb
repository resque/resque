require 'test_helper'
require 'resque/failure/redis'

unless defined?(JSON)
  module JSON
    class GeneratorError
    end
  end
end

describe "Resque::Failure::Redis" do
  before do
    @bad_string    = [39, 250, 141, 168, 138, 191, 52, 211, 159, 86, 93, 95, 39].map { |c| c.chr }.join
    exception      = StandardError.exception(@bad_string)
    worker         = Resque::Worker.new(:test)
    queue          = "queue"
    payload        = { "class" => Object, "args" => 3 }
    @redis_backend = Resque::Failure::Redis.new(exception, worker, queue, payload)
  end

  it 'cleans up bad strings before saving the failure, in order to prevent errors on the resque UI' do
    @redis_backend.save
    Resque::Failure::Redis.all # should not raise an error
  end

  it "only shows the backtrace for client code" do
    backtrace = ["show", "/lib/resque/job.rb", "hide"]

    failure = Resque::Failure::Redis.new(nil, nil, nil, nil)
    filtered_backtrace = failure.filter_backtrace(backtrace)

    assert_equal ["show"], filtered_backtrace
  end
  it "shows the whole backtrace when the exception happens before client code is reached" do
    backtrace = ["everything", "is", "shown"]

    failure = Resque::Failure::Redis.new(nil, nil, nil, nil)
    filtered_backtrace = failure.filter_backtrace(backtrace)

    assert_equal ["everything", "is", "shown"], filtered_backtrace
  end
end
