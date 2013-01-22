require 'test_helper'
require 'minitest/mock'

require 'resque/failure/ratchetio'

describe "Ratchetio failure class" do
  it "should be notified of an error" do
    exception = StandardError.new("BOOM")
    worker = Resque::Worker.new(:test)
    queue = "test"
    payload = {'class' => Object, 'args' => 66}

    ::Ratchetio = Minitest::Mock.new
    ::Ratchetio.expect(:report_exception, true, [exception, payload])

    backend = Resque::Failure::Ratchetio.new(exception, worker, queue, payload)
    backend.save

    ::Ratchetio.verify
  end
end
