require 'test_helper'
require 'resque/failure/hoptoad'
require 'mocha'
require 'hoptoad_notifier'

context "Hoptoad" do

  test "should be notified of an error" do
    exception = StandardError.new("BOOM")
    worker = Resque::Worker.new(:test)
    queue = "test"
    payload = {'class' => Object, 'args' => 66}

    HoptoadNotifier.expects(:notify_or_ignore).with(
      exception,
      :parameters => {:payload_class => 'Object', :payload_args => '66'})

    backend = Resque::Failure::Hoptoad.new(exception, worker, queue, payload)
    backend.save

  end

end
