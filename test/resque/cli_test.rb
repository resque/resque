require 'test_helper'

require 'resque/cli'

describe Resque::CLI do
  it "#work" do
    cli = Resque::CLI.new([], ["-c", "test/fixtures/resque.yml", "-i", "666", "-q", "first,second", "-r", "path/to/file"])
    w = mock("Resque::Worker")
    w.expects(:work)
    Resque::Worker.expects(:new).with(["first", "second"], {:timeout => 2, :interval => 666, :daemon => true}).returns(w)
    Resque::CLI.any_instance.expects(:load_enviroment).with("path/to/file")
    cli.invoke(:work)
  end
end
