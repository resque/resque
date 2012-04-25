require 'rack/test'
require 'resque/server'

module Resque
  module TestHelper
    class MiniTest::Unit::TestCase
      include Rack::Test::Methods
      def app
        Resque::Server.new
      end 

      def self.should_respond_with_success
        it "should respond with success" do
          assert last_response.ok?, last_response.errors
        end
      end
    end
  end
end
