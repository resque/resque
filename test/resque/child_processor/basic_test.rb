#TODO: change this require (dependent on much other refactoring)
require 'resque'
require 'mock_redis'

require 'test_helper'

require 'resque/worker'
require 'resque/child_processor/basic'

describe Resque::ChildProcessor::Basic do
  let(:client) { MiniTest::Mock.new }
  let(:worker) { Resque::Worker.new :foo, :client => client }

  describe "work" do
    it "each job happens in the main process" do
      r = MockRedis.new :host => "localhost", :port => 9736, :db => 0
      mock_redis = Redis::Namespace.new :resque, :redis => r
      Resque.redis = mock_redis

      job_results = Tempfile.new("job_results")

      Resque::Job.create("test_q", SelfLoggingTestJob, job_results.path)
      job = Resque::Job.reserve("test_q")
      child = Resque::ChildProcessor::Basic.new(worker)
      child.perform(job)

      job_results.rewind
      result = job_results.read
      assert_equal("SelfLoggingTestJob:#{Process.pid}", result)
    end
  end
end
