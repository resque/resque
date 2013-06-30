module Resque
  # Include this module in classes you wish to have logging facilities
  module Logging
    module_function

    # Thunk to the logger's own log method (if configured)
    def self.log(severity, message)
      Resque.logger.__send__(severity, message) if Resque.logger
    end

    # @!method debug(message)
    # @!method info(message)
    # @!method warn(message)
    # @!method error(message)
    # @!method fatal(message)
    #   @param message [String]
    #   @return [void]
    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method level do |message|
        Logging.log(level, message)
      end
    end
    module_function :debug, :info, :warn, :error, :fatal
  end
end
