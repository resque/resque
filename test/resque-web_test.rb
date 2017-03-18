require 'test_helper'
require 'rack/test'
require 'resque/server'

describe "Resque web" do
  include Rack::Test::Methods

  def app
    Resque::Server.new
  end

  # Root path test
  describe "on GET to /" do
    before { get "/" }

    it "redirect to overview" do
      follow_redirect!
    end
  end

  # Global overview
  describe "on GET to /overview" do
    before { get "/overview" }

    it "should at least display 'queues'" do
      assert last_response.body.include?('Queues')
    end
  end

  describe "With append-prefix option on GET to /overview" do
    reverse_proxy_prefix = 'proxy_site/resque'
    Resque::Server.url_prefix = reverse_proxy_prefix
    before { get "/overview" }

    it "should contain reverse proxy prefix for asset urls and links" do
      assert last_response.body.include?(reverse_proxy_prefix)
    end
  end

  # Working jobs
  describe "on GET to /working" do
    before { get "/working" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

  # Failed
  describe "on GET to /failed" do
    before { get "/failed" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

  # Stats
  describe "on GET to /stats/resque" do
    before { get "/stats/resque" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

  describe "on GET to /stats/redis" do
    before { get "/stats/redis" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

  describe "on GET to /stats/resque" do
    before { get "/stats/keys" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

  describe "also works with slash at the end" do
    before { get "/working/" }

    it "should respond with success" do
      assert last_response.ok?, last_response.errors
    end
  end

end

# Status check
context "on GET to /check_queue_sizes with default max size of 100" do
  setup {
    7.times { Resque.enqueue(SomeIvarJob, 20, '/tmp') }
    get "/check_queue_sizes"
  }

  should_respond_with_success

  test "should show message that the queue sizes are ok" do
    assert_equal 'Queue sizes are ok.', last_response.body
  end
end

context "on GET to /check_queue_sizes with a lower max size" do
  setup {
    7.times { Resque.enqueue(SomeIvarJob, 20, '/tmp') }
    get "/check_queue_sizes?max_queue_size=5"
  }

  should_respond_with_success

  test "should show message that the queue is backing up" do
    assert_equal 'Queue size has grown larger than max queue size.', last_response.body
  end
end
