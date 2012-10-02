require 'test_helper'

context "Resque.logger" do
  test "sets and receives the active logger" do
    my_logger = Object.new
    Resque.logger = my_logger
    assert_equal my_logger, Resque.logger
  end
end