require 'test_helper'
require 'minitest/mock'

require 'resque/failure/base'

class TestFailure < Resque::Failure::Base
end

describe "Base failure class" do
  it "allows calling all without throwing" do
    with_failure_backend TestFailure do
      assert_empty Resque::Failure.all
    end
  end
end
