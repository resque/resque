require 'test_helper'
require 'minitest/mock'

require 'resque/failure/thoughtbot'

class ThoughtbotFailure < Resque::Failure::Base
  include Resque::Failure::Thoughtbot
end

describe "Hoptoad and Airbrake failure class" do
  it "should be notified of an error" do
    exception = StandardError.new("BOOM")
    worker = Resque::Worker.new(:test)
    queue = "test"
    payload = {'class' => Object, 'args' => 66}

    mock = Minitest::Mock.new
    mock.expect :notify_or_ignore, nil, [ exception,
      { :parameters => { :payload_class => 'Object', :payload_args => '66' }} ]
    ThoughtbotFailure.klass = mock

    backend = ThoughtbotFailure.new(exception, worker, queue, payload)
    backend.save

    mock.verify
  end
end
