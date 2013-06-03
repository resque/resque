require 'test_helper'

require 'resque/globals'
require 'resque/child_process'
require 'resque/worker'

describe Resque::ChildProcess do
  let(:client) { MiniTest::Mock.new }

  describe "#reconnect" do
    it "delegates to the client" do
      client.expect :reconnect, nil
      worker = Resque::Worker.new :foo, :client => client
      child_process = Resque::ChildProcess.new(worker)
      child_process.reconnect
    end
  end
end
