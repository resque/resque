module Resque
  # Include this module in classes you wish to have logging facilities
  module Logging
    module_function

    # Thunk to the logger's own log method (if configured)
    def self.log(severity, message)
      Resque.logger.__send__(severity, message) if Resque.logger
    end
    
    # Log level aliases
    def debug(message); Logging.log :debug, message; end
    def info(message);  Logging.log :info,  message; end
    def warn(message);  Logging.log :warn,  message; end
    def error(message); Logging.log :error, message; end
    def fatal(message); Logging.log :fatal, message; end
  end
end