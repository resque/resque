require 'test_helper'

describe Resque::JobPerformer do
  before do
    @mock          = MiniTest::Mock.new
    @job_performer = Resque::JobPerformer.new
    @job_args = [:foo]
  end

  describe '#perform' do
    before do
      @options  = {
        :before => [
          :before_one,
          :before_two
        ],
        :around => [],
        :after  => [
          :after_one,
          :after_two
        ]
      }
    end

    it 'runs the before hooks' do
      @mock.expect :class, true
      @mock.expect :before_one, true, @job_args
      @mock.expect :before_two, true, @job_args
      @mock.expect :perform, true, @job_args
      @mock.expect :after_one, true, @job_args
      @mock.expect :after_two, true, @job_args
      @job_performer.perform(@mock, @job_args, @options).must_equal true
      @mock.verify
    end

    it 'returns false when a before mock raises DontPerform' do
      @options = {
        :before => [:before_one],
        :after  => [],
        :around => []
      }
      def @mock.before_one(*args)
        raise Resque::DontPerform
      end
      @mock.expect :class, true
      @mock.expect :perform, nil, @job_args
      @job_performer.perform(@mock, @job_args, @options).must_equal false
    end

    it 'supports the old and new job APIs' do
      class OldJob
        @queue = :old
        def self.perform args
          true
        end
      end

      class NewJob
        @queue = :new
        def perform args
          true
        end
      end

      @options = {
        :before => [],
        :after  => [],
        :around => []
      }

      @job_performer.perform(OldJob.new, [:foo], @options).must_equal true
      @job_performer.perform(NewJob.new, [:foo], @options).must_equal true
    end

    describe 'when around_perform is present' do
      before do
        @options = {
          :before => [],
          :around => [
            :around_one,
            :around_two
          ],
          :after => []
        }
      end

      it 'runs the around hooks' do
        @mock.expect :class, true
        @mock.expect :perform, true, @job_args
        @mock.expect :around_two, true, @job_args
        @mock.expect :around_one, true, @job_args
        def @mock.around_two(*args)
          method_missing(:around_two, *args)
          yield
        end
        def @mock.around_one(*args)
          method_missing(:around_one, *args)
          yield
        end
        @job_performer.perform(@mock, @job_args, @options)
        @mock.verify
      end
    end
  end
end
