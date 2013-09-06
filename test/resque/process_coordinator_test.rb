require 'test_helper'

describe Resque::ProcessCoordinator do
  let(:process_coordinator) { Resque::ProcessCoordinator.new }

  describe "#worker_pids" do
    it "should return worker pids for each OS" do
      with_constants :RUBY_PLATFORM => "solaris" do
        assert_equal process_coordinator.worker_pids, ["11111"]
      end

      with_constants :RUBY_PLATFORM => "mingw32" do
        assert_equal process_coordinator.worker_pids, ["5244"]
      end

      with_constants :RUBY_PLATFORM => "linux" do
        assert_equal process_coordinator.worker_pids, ["22222"]
      end
    end

    def with_constants(constants, &block)
      saved_constants = {}
      constants.each do |constant, val|
        saved_constants[ constant ] = Object.const_get( constant )
        Kernel::silence_warnings { Object.const_set( constant, val ) }
      end

      begin
        block.call
      ensure
        constants.each do |constant, val|
          Kernel::silence_warnings { Object.const_set( constant, saved_constants[ constant ] ) }
        end
      end
    end
  end
end