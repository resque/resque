require 'test_helper'

require 'resque/worker'
require 'resque/child_processor/fork'

describe Resque::ChildProcessor::Fork do
  let(:client) { MiniTest::Mock.new }

  describe "#reconnect" do
    it "delegates to the client" do
      client.expect :reconnect, nil
      worker = Resque::Worker.new :foo, :client => client
      child_process = Resque::ChildProcessor::Fork.new(worker)
      child_process.reconnect
    end
  end
end
