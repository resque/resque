# coding: US-ASCII
# This test treat ascii-8bit, so this is split from test/resque_test.rb
require 'test_helper'

describe "Resque" do
  before do
    Resque.backend.store.flushall
    @original_redis = Resque.backend.store
  end

  after do
    Resque.redis = @original_redis
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE != "rbx"
    # See https://github.com/resque/resque/issues/769
    it "rescues jobs with invalid UTF-8 characters" do
      Resque.logger = DummyLogger.new
      begin
        Resque.enqueue(SomeMethodJob, "Invalid UTF-8 character \xFF")
        messages = Resque.logger.messages
      rescue Exception => e
        assert false, e.message
      ensure
        reset_logger
      end
      assert_match(/Invalid UTF-8 character/, messages.first)
    end
  end
end
