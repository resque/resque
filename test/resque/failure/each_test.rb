require 'test_helper'
require 'resque/failure/redis'

describe Resque::Failure::Each do
  after do
    Resque::Failure.clear
  end

  describe 'each' do
    it 'properly iterates over the default range for a single failure' do
      save_failures('T1')

      n = 0
      Resque::Failure::Redis.each do |i, failure|
        assert_equal 0, i
        assert_equal 'T1', failure['payload']['class']
        n = n + 1
      end

      assert_equal 1, n
    end

    it 'properly iterates over the default range for multiple failures' do
      expected_failure_classes = ['T1', 'T2']
      save_failures('T1', 'T2')

      n = 0
      Resque::Failure::Redis.each do |i, failure|
        assert_equal n, i
        assert_equal expected_failure_classes[n], failure['payload']['class']
        n = n + 1
      end

      assert_equal 2, n
    end

    it 'properly iterates over the specified range for multiple failures' do
      save_failures('T1', 'T2', 'T3')

      n = 0
      Resque::Failure::Redis.each(1, 1) do |i, failure|
        assert_equal 1, i
        assert_equal 'T2', failure['payload']['class']
        n = n + 1
      end

      assert_equal 1, n
    end

    it 'only finds the desired classes of errors' do
      save_failures('T1', 'T2')

      n = 0
      Resque::Failure::Redis.each(0, 2, :failed, 'T2') do |i, failure|
        assert_equal 1, i
        assert_equal 'T2', failure['payload']['class']
        n = n + 1
      end

      assert_equal 1, n
    end

    it 'only finds the desired classes of errors within the specified range' do
      save_failures('T1', 'T2', 'T2', 'T3')

      n = 0
      Resque::Failure::Redis.each(2, 4, :failed, 'T2') do |i, failure|
        assert_equal 2, i
        assert_equal 'T2', failure['payload']['class']
        n = n + 1
      end

      assert_equal 1, n
    end
  end

  private

  def save_failures(*classes)
    classes.each do |klass|
      failure = Resque::Failure::Redis.new(Exception.new,
                                           nil, :test, {'class' => klass})
      failure.save
    end
  end
end
