require 'test_helper'

require 'resque/cli'

describe Resque::CLI do
  describe "#work" do
    it "does its thing" do
      worker = MiniTest::Mock.new.expect(:work, "did some work!")

      Resque::Worker.stub(:new, worker) do
        cli = Resque::CLI.new([], ["-c", "test/fixtures/resque.yml", "-i", "666", "-q", "first,second", "-r", "path/to/file"])
        assert_equal "did some work!", cli.invoke(:work)
      end
    end
  end

	describe "#list" do
		describe "no workers" do
			it "displays None" do
				cli = Resque::CLI.new([], ["-c", "test/fixtures/resque.yml", "--redis", "localhost:6379/resque"])
				out, err = capture_io do
					cli.invoke(:list)
				end

				assert_equal "None", out.chomp
			end
		end

		describe "with a worker" do
			it "displays worker state" do
				registry = MiniTest::Mock.new
				registry.expect(:all, [MiniTest::Mock.new.expect(:state, "working")])
				Resque::WorkerRegistry = registry

				cli = Resque::CLI.new([], ["-c", "test/fixtures/resque.yml", "--redis", "localhost:6379/resque"])
				out, err = capture_io do
					cli.invoke(:list)
				end

				assert_match /\(working\)/, out.chomp
			end
		end
	end
end
