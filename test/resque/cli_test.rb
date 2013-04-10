require 'test_helper'

require 'resque/cli'

describe Resque::CLI do
  it "#work" do
    worker = MiniTest::Mock.new
    worker.expect(:new, MiniTest::Mock.new.expect(:work, nil), [["first", "second"], {:timeout => 2, :interval => 666, :daemon => true}])

    Resque::Worker = worker

    cli = Resque::CLI.new([], ["-c", "test/fixtures/resque.yml", "-i", "666", "-q", "first,second", "-r", "path/to/file"])
    cli.invoke(:work)
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
