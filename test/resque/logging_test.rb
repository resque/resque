require 'test_helper'
require 'minitest/mock'

require 'resque/globals'
require 'resque/logging'

actual_logger = Resque.logger

describe "Resque::Logging" do
  after do
    Resque.logger = actual_logger
  end

  it "sets and receives the active logger" do
    my_logger = Object.new
    Resque.logger = my_logger
    assert_equal my_logger, Resque.logger
  end

  %w(debug info error fatal).each do |severity|
    it "logs #{severity} messages" do
      message       = "test message"
      mock_logger   = MiniTest::Mock.new
      mock_logger.expect severity.to_sym, nil, [message]
      Resque.logger = mock_logger

      Resque::Logging.send severity, message
      mock_logger.verify
    end
  end
end
