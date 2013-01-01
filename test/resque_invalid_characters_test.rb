# coding: US-ASCII
# This test treat ascii-8bit, so this is split from test/resque_test.rb
require 'test_helper'

describe "Resque" do
  before do
    Resque.redis.flushall

    Resque.push(:people, { 'name' => 'chris' })
    Resque.push(:people, { 'name' => 'bob' })
    Resque.push(:people, { 'name' => 'mark' })
    @original_redis = Resque.redis
  end

  after do
    Resque.redis = @original_redis
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE != "rbx"
    # See https://github.com/defunkt/resque/issues/769
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
      message = "Invalid UTF-8 character in job: \"\\xFF\" from ASCII-8BIT to UTF-8"
      assert_includes messages, message
    end
  end
end
