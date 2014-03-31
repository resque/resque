require 'test_helper'

module Resque
  describe Job do
    class ::DummyJob
      def self.perform
      end
    end

    subject { Resque::Job.new(:jobs, {'class' => DummyJob}) }

    describe "#fail(exception)" do
      let(:failure) { "Resque::Failure" }

      def assert_created_failure(assertion, exception)
        Failure.stub(:create, failure) do
          assert_equal(assertion, subject.fail(exception))
        end
      end

      describe "a Resque::DontFail exception is NOT raised" do
        it "should create the failure" do
          assert_created_failure(failure, DirtyExit.new)
        end
      end

      describe "a Resque::DontFail exception is raised" do
        it "should not create the failure" do
          assert_created_failure(nil, DontFail.new)
        end
      end
    end
  end
end
