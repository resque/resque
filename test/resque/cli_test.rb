require 'test_helper'
require 'resque/cli'

describe Resque::CLI do

  describe "#initialize" do
    it "uses a default redis without a specified option" do
      stubbed_redis = lambda { |server|
        assert_equal 'localhost:6379/resque', server
      }
      Resque.stub(:redis=, stubbed_redis) do
        Resque::CLI.new
      end
    end
  end

  describe "#work" do
    it "does its thing" do
      Resque::Worker.stub(:new, MiniTest::Mock.new.expect(:work, "did some work!")) do
        cli = Resque::CLI.new
        assert_equal "did some work!", cli.work
      end
    end
  end

  describe "#list" do
    describe "no workers" do
      it "displays None" do
        Resque::WorkerRegistry.stub(:all, []) do
          cli = Resque::CLI.new
          out, _ = capture_io { cli.list }
          assert_equal "None", out.chomp
        end
      end
    end

    describe "with a worker" do
      it "displays worker state" do
        Resque::WorkerRegistry.stub(:all, [MiniTest::Mock.new.expect(:state, "working")]) do
          cli = Resque::CLI.new
          out, _ = capture_io { cli.list }
          assert_match(/\(working\)/, out.chomp)
        end
      end
    end
  end

  describe "#kill" do
    it "displays killed" do
      Process.stub(:kill, nil) do
        Resque::WorkerRegistry.stub(:remove, nil) do
          cli = Resque::CLI.new
          out, _ = capture_io { cli.kill("worker:123") }
          assert_match(/killed/, out.chomp)
        end
      end
    end
  end

  describe "#remove" do
    it "displays removed" do
      Resque::WorkerRegistry.stub(:remove, nil) do
        cli = Resque::CLI.new #move this to a subject?
        out, _ = capture_io { cli.remove("worker:123") }
        assert_match(/removed/, out.chomp)
      end
    end
  end

  describe 'migrate_failures' do
    it 'migrates existing failure queues from lists to hashes with ids' do
      redis = Resque.backend.store
      redis.flushall

      redis.pipelined do
        3.times do
          failure = Resque::Failure.new(
            :raw_exception => Exception.new,
            :queue => 'awesome',
            :payload => { 'class' => 'George', 'args' => 'Harrison' }
          )
          redis.rpush :failed, failure.data
          redis.rpush :foo_failed, failure.data
          redis.sadd :failed_queues, :foo_failed
        end
      end

      cli = Resque::CLI.new
      out, _ = capture_io { cli.migrate_failures }
      assert_match /Done!/, out.chomp
      assert_equal 'hash', redis.type(:failed)
      assert_equal 'hash', redis.type(:foo_failed)
      assert_equal 3, redis.hlen(:failed)
      assert_equal 3, redis.zcard(:failed_ids)
      assert_equal 3, redis.hlen(:foo_failed)
      assert_equal 3, redis.zcard(:foo_failed_ids)

      redis.flushall
    end
  end
end

