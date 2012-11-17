require 'test_helper'
require 'resque/server/test_helper'

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

# Working jobs
describe "on GET to /working" do
  before { get "/working" }

  should_respond_with_success
end

# Failed
describe "on GET to /failed" do
  before { get "/failed" }

  should_respond_with_success
end

# Stats
describe "on GET to /stats/resque" do
  before { get "/stats/resque" }

  should_respond_with_success
end

describe "on GET to /stats/redis" do
  before { get "/stats/redis" }

  should_respond_with_success
end

describe "on GET to /stats/resque" do
  before { get "/stats/keys" }

  should_respond_with_success
end

describe "also works with slash at the end" do
  before { get "/working/" }

  should_respond_with_success
end

describe "on POST to /failed/requeue/all" do
  before {
    add_failed_jobs
    post "/failed/requeue/all"
  }

  it "should redirect to /failed and contain '0 jobs'" do
    follow_redirect!
    assert last_response.body.include?('<b>0</b> jobs')
  end
end
