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

  describe "#sort_failures" do
    it "sorts the 'failed' queue for the redis_multi_queue failure backend" do
      Resque.backend.store.flushall

      failures = 3.times.map do |i|
        Resque::Failure::Redis.new(Exception.new,
                                           nil, "sample_#{i%2}".to_sym,
                                           {'class' => 'some_class',
                                            'args' => 'some_args'})
      end
      failures.each(&:save)

      cli = Resque::CLI.new
      capture_io { cli.sort_failures }
      assert_equal(Resque.backend.store.llen('sample_0_failed').to_i, 2)
      assert_equal(Resque.backend.store.llen('sample_1_failed').to_i, 1)

      Resque.backend.store.flushall
    end
  end
end

