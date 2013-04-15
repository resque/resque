require File.join(File.expand_path(File.dirname(__FILE__)), 'test_helper')

require 'resque/cli'

describe Resque::CLI do
  describe "#work" do
    it "does its thing" do
      Resque::Worker.stub(:new, MiniTest::Mock.new.expect(:work, "did some work!")) do
        cli = Resque::CLI.new
        assert_equal "did some work!", cli.invoke(:work)
      end
    end
  end

  describe "#list" do
    describe "no workers" do
      it "displays None" do
        Resque::WorkerRegistry.stub(:all, []) do
          cli = Resque::CLI.new
          out, _ = capture_io { cli.invoke(:list) }
          assert_equal "None", out.chomp
        end
      end
    end

    describe "with a worker" do
      it "displays worker state" do
        Resque::WorkerRegistry.stub(:all, [MiniTest::Mock.new.expect(:state, "working")]) do
          cli = Resque::CLI.new
          out, _ = capture_io { cli.invoke(:list) }
          assert_match(/\(working\)/, out.chomp)
        end
      end
    end
  end
end

