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
end
