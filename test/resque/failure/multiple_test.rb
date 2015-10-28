require 'test_helper'
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'resque/failure/base'

describe Resque::Failure::Multiple do
  after do
    Resque::Failure::Multiple.classes = []
  end

  describe '.requeue_queue' do
    let(:backends) { [Minitest::Mock.new, Minitest::Mock.new] }

    it 'calls .requeue_queue for the classes' do
      Resque::Failure::Multiple.classes = backends

      backends[0].expect :requeue_queue, nil, ['foo']
      backends[1].expect :requeue_queue, nil, ['foo']

      Resque::Failure::Multiple.requeue_queue('foo')
    end
  end
end
