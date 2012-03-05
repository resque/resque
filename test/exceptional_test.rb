require 'test_helper'

begin
  require 'exceptional'
rescue LoadError
  warn "Install exceptional gem to run Exceptional tests."
end

if defined? Exceptional
  require 'resque/failure/exceptional'
  context "Exceptional" do
    test "should be notified of an error" do
      exception = StandardError.new("BOOM")
      worker = Resque::Worker.new(:test)
      queue = "test"
      payload = {'class' => Object, 'args' => 66}

      Exceptional.expects(:notify_or_ignore).with(
        exception,
        :parameters => {:payload_class => 'Object', :payload_args => '66'})

      backend = Resque::Failure::Exceptional.new(exception, worker, queue, payload)
      backend.save
    end
  end
end
