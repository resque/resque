require 'test_helper'
require 'rack/test'
require 'resque/server'

describe "Resque web" do
  include Rack::Test::Methods

  def app
    Resque::Server.new
  end

  def default_host
    'localhost'
  end

  def create_failure
    Resque::Failure.create(exception: StandardError.new('boom'), worker: Resque::Worker.new(:jobs),
                           queue: 'jobs', payload: { 'class' => 'SomeJob', 'args' => [] })
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

    before do
      Resque::Server.url_prefix = reverse_proxy_prefix
      get "/overview"
    end

    after { Resque::Server.url_prefix = nil }

    it "should contain reverse proxy prefix for asset urls and links" do
      assert last_response.body.include?(reverse_proxy_prefix)
    end
  end

  describe "on a state-changing request" do
    before do
      Resque::Job.create(:jobs, 'SomeJob')
      create_failure
    end

    it "rejects cross-site browser requests" do
      [
        { 'HTTP_SEC_FETCH_SITE' => 'cross-site' },
        { 'HTTP_SEC_FETCH_SITE' => 'same-site' },
        { 'HTTP_SEC_FETCH_SITE' => 'cross-site', 'HTTP_ORIGIN' => 'http://localhost' },
        { 'HTTP_ORIGIN' => 'http://evil.example' },
        { 'HTTP_ORIGIN' => 'null' }
      ].each do |headers|
        post "/failed/clear", {}, headers
        assert_equal 403, last_response.status, headers.inspect

        post "/queues/jobs/remove", {}, headers
        assert_equal 403, last_response.status, headers.inspect
      end

      assert_equal 1, Resque::Failure.count
      assert_equal 1, Resque.size(:jobs)
    end

    it "allows same-origin and non-browser requests" do
      [
        { 'HTTP_SEC_FETCH_SITE' => 'same-origin' },
        { 'HTTP_SEC_FETCH_SITE' => 'none' },
        { 'HTTP_ORIGIN' => 'http://localhost' },
        { 'HTTP_ORIGIN' => 'https://localhost' },
        {}
      ].each do |headers|
        create_failure
        post "/failed/clear", {}, headers

        assert_equal 302, last_response.status, headers.inspect
        assert_equal 0, Resque::Failure.count, headers.inspect
      end
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
  describe "on POST to /queues/:id/remove-job" do
    before do
      Resque::Job.create(:jobs, 'SomeJob', 20, '/tmp')
      Resque::Job.create(:jobs, 'SomeJob', 30, '/tmp')
      Resque::Job.create(:jobs, 'OtherJob')
      Resque::Job.create(:jobs, 'OtherJob')
    end

    def payload_for(klass, *args)
      Resque.encode('class' => klass, 'args' => args)
    end

    it "removes only the job whose payload was submitted" do
      post "/queues/jobs/remove-job", :payload => payload_for('SomeJob', 20, '/tmp')

      follow_redirect!
      assert last_response.ok?, last_response.errors
      assert_equal 3, Resque.size(:jobs)
      assert_equal [30, '/tmp'], Resque.peek(:jobs)['args']
    end

    it "does not take sibling jobs of the same class with it" do
      post "/queues/jobs/remove-job", :payload => payload_for('OtherJob')

      assert_equal 2, Resque.size(:jobs)
      remaining = Resque.peek(:jobs, 0, 2).map { |job| job['class'] }
      assert_equal ['SomeJob', 'SomeJob'], remaining
    end

    it "rejects a payload that is not valid JSON" do
      post "/queues/jobs/remove-job", :payload => 'not json'

      assert_equal 400, last_response.status
      assert_equal 4, Resque.size(:jobs)
    end

    it "rejects a missing payload" do
      post "/queues/jobs/remove-job"

      assert_equal 400, last_response.status
      assert_equal 4, Resque.size(:jobs)
    end
  end

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

  describe "on a failed job" do
    before do
      create_failure
    end

    it "renders Retry and Remove as POST forms" do
      get "/failed"
      body = CGI.unescapeHTML(last_response.body)

      assert_includes body, %(<form method="POST" action="/failed/requeue/0" class="retry">)
      assert_includes body, %(<form method="POST" action="/failed/remove/0">)
    end

    it "retries over POST" do
      post "/failed/requeue/0", {}, 'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'

      assert_equal Resque::Failure.all(0)['retried_at'], last_response.body
      assert_equal 1, Resque.size(:jobs)
    end

    it "removes over POST" do
      post "/failed/remove/0"

      assert_equal 302, last_response.status
      assert_equal 0, Resque::Failure.count
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
