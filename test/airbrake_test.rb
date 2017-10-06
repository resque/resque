
require 'test_helper'

begin
  require 'airbrake'
rescue LoadError
  warn "Install airbrake gem to run Airbrake tests."
end

if defined? Airbrake
  require 'resque/failure/airbrake'
  describe "Airbrake" do
    it "should be notified of an error" do
      exception = StandardError.new("BOOM")
      worker = Resque::Worker.new(:test)
      queue = "test"
      payload = {'class' => Object, 'args' => 66}

      notify_method =
        if Airbrake::AIRBRAKE_VERSION.to_i < 5
          :notify
        else
          :notify_sync
        end

      Airbrake.expects(notify_method).with(
        exception,
        :parameters => {:payload_class => 'Object', :payload_args => '66'})

      backend = Resque::Failure::Airbrake.new(exception, worker, queue, payload)
      backend.save
    end
  end
end
