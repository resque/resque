require 'test_helper'
require 'resque/failure/multiple'

describe "Resque::Failure::Multiple" do
  class BrokenBackend < Resque::Failure::Base
    class OriginalError < RuntimeError
    end

    def save
      raise OriginalError, "Raise error always"
    end
  end

  let(:exception) { StandardError.exception('some error') }
  let(:worker) { Resque::Worker.new(:test) }
  let(:payload) { { "class" => Object, "args" => 3 } }

  it 'requeue_all and does not raise an exception' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [Resque::Failure::Redis]

      Resque::Failure.create({:exception => exception, :worker => worker, :queue => "queue", :payload => payload})
      Resque::Failure::Multiple.requeue_all # should not raise an error
    end
  end

  it 'call #save to all backends even if some backends fail' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [BrokenBackend, Resque::Failure::Redis]
      Resque::Failure::Redis.any_instance.expects(:save)

      assert_raises(Resque::Failure::Multiple::BackendError) {
        Resque::Failure.create({:exception => exception, :worker => worker, :queue => "queue", :payload => payload})
      }
    end
  end

  it 'raises BackendError with original error when some backends fail' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [BrokenBackend, Resque::Failure::Redis]

      begin
        Resque::Failure.create({:exception => exception, :worker => worker, :queue => "queue", :payload => payload})
      rescue Resque::Failure::Multiple::BackendError => err
        assert_equal err.original_errors.keys.size, 1
        assert_instance_of BrokenBackend::OriginalError, err.original_errors[BrokenBackend]
      else
        raise "Expect to raise BackendError but not raised"
      end
    end
  end
end
