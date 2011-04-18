require 'test_helper'
require 'resque/server/test_helper'
 
# Root path test
context "on GET to /" do
  setup { get "/" }

  test "redirect to overview" do
    follow_redirect!
  end
end

# Global overview
context "on GET to /overview" do
  setup { get "/overview" }

  test "should at least display 'queues'" do
    assert last_response.body.include?('Queues')
  end
end

# Working jobs
context "on GET to /working" do
  setup { get "/working" }

  should_respond_with_success
end

# Failed
context "on GET to /failed" do
  setup { get "/failed" }

  should_respond_with_success
end

# Stats 
context "on GET to /stats/resque" do
  setup { get "/stats/resque" }

  should_respond_with_success
end

context "on GET to /stats/redis" do
  setup { get "/stats/redis" }

  should_respond_with_success
end

context "on GET to /stats/resque" do
  setup { get "/stats/keys" }

  should_respond_with_success
end

# Status check
context "on GET to /check_queue_sizes with default max size of 100" do
  setup {
    7.times { Resque.enqueue(SomeIvarJob, 20, '/tmp') }
    get "/check_queue_sizes"
  }

  should_respond_with_success

  test "should show message that the queue sizes are ok" do
    assert last_response.body.include?('Queue sizes are ok')
  end
end

context "on GET to /check_queue_sizes with a lower max size" do
  setup {
    7.times { Resque.enqueue(SomeIvarJob, 20, '/tmp') }
    get "/check_queue_sizes?max_queue_size=5"
  }

  should_respond_with_success

  test "should show message that the queue is backing up" do
    assert last_response.body.include?('Queue size has grown larger than max queue size.')
  end
end
