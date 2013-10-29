require 'test_helper'

describe Resque::JobPerformer do
  let(:mock) { MiniTest::Mock.new }
  let(:job_performer) { Resque::JobPerformer.new }
  let(:job_args) { [:foo] }

  describe '#perform' do
    let(:options) {
      {
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
    }

    it 'runs the before hooks' do
      mock.expect :before_one, true, job_args
      mock.expect :before_two, true, job_args
      mock.expect :perform, true, job_args
      mock.expect :after_one, true, job_args
      mock.expect :after_two, true, job_args
      job_performer.perform(mock, job_args, options).must_equal true
      mock.verify
    end

    describe "mock raises DontPerform" do
      let(:options) {
        {
          :before => [:before_one],
          :after  => [],
          :around => []
        }
      }

      it 'should return false' do
        def mock.before_one(*args)
          raise Resque::DontPerform
        end

        mock.expect :perform, nil, job_args
        job_performer.perform(mock, job_args, options).must_equal false
      end
    end

    describe 'when around_perform is present' do
      let(:options) {
        {
          :before => [],
          :around => [
            :around_one,
            :around_two
          ],
          :after => []
        }
      }

      it 'runs the around hooks' do
        mock.expect :perform, true, job_args
        mock.expect :around_two, true, job_args
        mock.expect :around_one, true, job_args
        def mock.around_two(*args)
          method_missing(:around_two, *args)
          yield
        end
        def mock.around_one(*args)
          method_missing(:around_one, *args)
          yield
        end
        job_performer.perform(mock, job_args, options)
        mock.verify
      end
    end
  end
end
