module Resque
  class QuietFormatter
    def call(severity, datetime, progname, msg)
      ""
    end
  end
end
