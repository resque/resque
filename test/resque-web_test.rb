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

  # Queues
  describe "on GET to /queues" do
    before { Resque::Failure.stubs(:count).returns(1) }

    describe "with Resque::Failure::RedisMultiQueue backend enabled" do
      it "should display failed queues" do
        with_failure_backend Resque::Failure::RedisMultiQueue do
          Resque::Failure.stubs(:queues).returns(
            [:queue1_failed, :queue2_failed]
          )

          get "/queues"
        end

        assert last_response.body.include?('queue1_failed')
        assert last_response.body.include?('queue2_failed')
      end

      it "should respond with success when no failed queues exists" do
        with_failure_backend Resque::Failure::RedisMultiQueue do
          Resque::Failure.stubs(:queues).returns([])

          get "/queues"
        end

        assert last_response.ok?, last_response.errors
      end
    end

    describe "Without Resque::Failure::RedisMultiQueue backend enabled" do
      it "should display queues when there are more than 1 failed queue" do
        Resque::Failure.stubs(:queues).returns(
          [:queue1_failed, :queue2_failed]
        )
        get "/queues"

        assert last_response.body.include?('queue1_failed')
        assert last_response.body.include?('queue2_failed')
      end

      it "should display 'failed' queue when there is 1 failed queue" do
        Resque::Failure.stubs(:queues).returns([:queue1])
        get "/queues"

        assert !last_response.body.include?('queue1')
        assert last_response.body.include?('failed')
      end

      it "should respond with success when no failed queues exists" do
        Resque::Failure.stubs(:queues).returns([])
        get "/queues"

        assert last_response.ok?, last_response.errors
      end
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
