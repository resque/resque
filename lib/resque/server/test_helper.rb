require 'rack/test'
require 'resque/server'

module Resque
  module TestHelper
    class Test::Unit::TestCase
      include Rack::Test::Methods
      def app
        Resque::Server.new
      end 

      def self.should_respond_with_success
        test "should respond with success" do
          assert last_response.ok?, last_response.errors
        end
      end

      def self.should_contain(text)
        test "should contain text" do
          assert last_response.body.include?(text)
        end
      end
    end
  end
end
