module Resque
  # Include this module in classes you wish to have logging facilities
  module Logger
    module_function

    # Log level aliases
    def debug(message); __log__ :debug, message; end
    def info(message);  __log__ :info,  message; end
    def warn(message);  __log__ :warn,  message; end
    def error(message); __log__ :error, message; end
    def fatal(message); __log__ :fatal, message; end

    # Low-level thunk to the logger's own log method
    def __log__(severity, message)
      Resque.logger.__send__(severity, message) if Resque.logger
    end
  end
end