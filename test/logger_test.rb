require 'test_helper'
require 'minitest/mock'

context "Resque.logger" do
  test "sets and receives the active logger" do
    my_logger = Object.new
    Resque.logger = my_logger
    assert_equal my_logger, Resque.logger
  end
end

context "Resque::Logger" do
  %w(debug info error fatal).each do |severity|
    test "logs #{severity} messages" do
      message       = "test message"
      mock_logger   = MiniTest::Mock.new
      mock_logger.expect severity.to_sym, nil, [message]
      Resque.logger = mock_logger

      Resque::Logger.send severity, message
      mock_logger.verify
    end
  end
end