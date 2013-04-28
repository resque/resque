require 'test_helper'
require 'resque'
require 'resque/failure'
require 'resque/failure/base'

shared_examples_for 'A Failure Backend' do
  describe '.count' do
    it 'returns the number of failures' do
      Resque::Failure.count.must_equal 2
    end
  end

  describe '.queues' do
    it 'returns an array of all the available queues' do
      Resque::Failure.queues.must_equal ["jobs_failed"]
    end
  end

  describe '.all' do
    it 'returns an array of all the failures' do
      Resque::Failure.all(0,2,:jobs_failed).must_equal [{"failure_data"=>"blahblah"},{"failure_data"=>"blahblah"}]
    end
  end

  describe '.each' do
    it 'returns an enumerator of all the failures' do
      Resque::Failure.each do |f|
        f.must_equal({"failure_data"=>"blahblah"})
      end
    end
  end

  describe '.clear' do
    it 'removes all failed jobs' do
      Resque::Failure.clear
      Resque::Failure.all.must_equal nil
    end
  end

  describe '.remove' do
    it 'removes a single failed job' do
    end
  end
  
  describe '.requeue' do
    it 'requeues a job'
  end
end
