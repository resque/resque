require 'test_helper'
require 'resque/failure/multiple'

describe "Resque::Failure::Multiple" do

  it 'requeue_all and does not raise an exception' do
    with_failure_backend(Resque::Failure::Multiple) do
      Resque::Failure::Multiple.classes = [Resque::Failure::Redis]
      exception = StandardError.exception('some error')
      worker = Resque::Worker.new(:test)
      payload = { "class" => Object, "args" => 3 }
      Resque::Failure.create({:exception => exception, :worker => worker, :queue => "queue", :payload => payload})
      Resque::Failure::Multiple.requeue_all # should not raise an error
    end
  end
end
