require 'test_helper'
require 'resque/failure/multiple'

describe 'Resque::Failure::Multiple' do
  it 'requeue_all and does not raise an exception' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [Resque::Failure::Redis]
      exception = StandardError.exception('some error')
      worker = Resque::Worker.new(:test)
      payload = { 'class' => 'Object', 'args' => 3 }
      Resque::Failure.create({:exception => exception, :worker => worker, :queue => 'queue', :payload => payload})
      Resque::Failure::Multiple.requeue_all # should not raise an error
    end
  end

  it 'requeue_queue delegates to the first class and returns a mapped queue name' do
    with_failure_backend(Resque::Failure::Multiple) do
      mock_class = Minitest::Mock.new
      mock_class.expect(:requeue_queue, 'mapped_queue', ['queue'])
      Resque::Failure::Multiple.classes = [mock_class]
      assert_equal 'mapped_queue', Resque::Failure::Multiple.requeue_queue('queue')
    end
  end

  it 'remove passes the queue on to its backend' do
    with_failure_backend(Resque::Failure::Multiple) do
      mock = Object.new
      def mock.remove(_id, queue)
        @queue = queue
      end

      Resque::Failure::Multiple.classes = [mock]
      Resque::Failure::Multiple.remove(1, :test_queue)
      assert_equal :test_queue, mock.instance_variable_get('@queue')
    end
  end
end
