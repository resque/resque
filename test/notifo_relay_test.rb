require 'test_helper'

begin
  require 'notifo'
rescue LoadError
  warn "Install notifo gem to run Notifo tests."
end

if defined? Notifo
  require 'resque/failure/notifo_relay'

  context "Notifo Relay" do

    setup do
      Resque::Failure::NotifoRelay.username = "auser"
      Resque::Failure::NotifoRelay.api_secret = "shhhh"
    end

    test "defines username" do
      assert_equal "auser", Resque::Failure::NotifoRelay.username  
    end

    test "defines api_secret" do
      assert_equal "shhhh", Resque::Failure::NotifoRelay.api_secret
    end

    test "should be notified of an error" do
      exception = StandardError.new("BOOM")
      worker = Resque::Worker.new(:test)
      queue = "test"
      payload = {'class' => Object, 'args' => 66}

      Notifo.any_instance.expects(:post).with("auser", "Resque failure: #{exception.class.to_s}")

      backend = Resque::Failure::NotifoRelay.new(exception, worker, queue, payload)
      backend.save
    end
  end
end
