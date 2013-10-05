require 'test_helper'
require 'resque/worker_registry'

describe Resque::WorkerRegistry do
  let(:worker_options){ { :interval => 0, :timeout => 0, :logger => MonoLogger.new("/dev/null")} }

  before :each do
    Resque.backend.store.flushall
  end

  class Resque::Worker
    def <=>(other)
      self.to_s <=> other.to_s
    end
  end

  describe "all" do
    it "returns an empty array if no workers exist" do
      assert_equal [], Resque::WorkerRegistry.all
    end

    it "returns an array of all worker objects" do
      all_queues = []

      [:jobs, :other_jobs, :more_jobs].each do |queue|
        worker = Resque::Worker.new(queue, worker_options)
        worker.worker_registry.register
        all_queues << worker
      end
      assert_equal all_queues.sort, Resque::WorkerRegistry.all.sort
    end
  end

  describe "working" do
    it "returns an empty array if no worker objects are processing" do
      [:jobs, :other_jobs, :more_jobs].each do |queue|
        worker = Resque::Worker.new(queue, worker_options)
        worker.worker_registry.register
      end
      assert_equal [], Resque::WorkerRegistry.working
    end

    it "returns an array of worker objects currently processing" do
      [:jobs, :other_jobs, :more_jobs].each do |queue|
        worker = Resque::Worker.new(queue, worker_options)
        worker.worker_registry.register
      end

      worker = Resque::Worker.new(:working_job, worker_options)
      worker.worker_registry.register

      worker.work_loop do
        assert_equal 4, Resque::WorkerRegistry.all.count
        assert_equal [worker], Resque::WorkerRegistry.working
      end
    end
  end

  describe "unregister" do
    it "removes the worker from the registry" do
      worker = Resque::Worker.new(:jobs, worker_options)
      worker.worker_registry.register
      assert_equal 1, Resque::WorkerRegistry.all.count

      worker.worker_registry.unregister
      assert_equal [], Resque::WorkerRegistry.all
    end
  end
end
