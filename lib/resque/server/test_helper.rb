require 'rack/test'
require 'resque/server'

module Resque
  module TestHelper
    class MiniTest::Unit::TestCase
      include Rack::Test::Methods
      def app
        Resque::Server.new
      end

      def add_failed_jobs
        Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(:test), :queue => "queue", :payload => {'class' => 'TestClass'})
        Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(:test), :queue => "queue", :payload => {'class' => 'TestClass'})
        Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(:test), :queue => "queue", :payload => {'class' => 'TestClass'})
        Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(:test), :queue => "queue", :payload => {'class' => 'TestClass'})
      end

      def self.should_respond_with_success
        it "should respond with success" do
          assert last_response.ok?, last_response.errors
        end
      end
    end
  end
end
