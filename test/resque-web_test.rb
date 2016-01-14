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

context "With append-prefix option on GET to /overview" do
  reverse_proxy_prefix = 'proxy_site/resque'
  Resque::Server.url_prefix = reverse_proxy_prefix
  setup { get "/overview" }

  test "should contain reverse proxy prefix for asset urls and links" do
    assert last_response.body.include?(reverse_proxy_prefix)
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

context "also works with slash at the end" do
  setup { get "/working/" }

  should_respond_with_success
end
