module Resque
  class VerboseFormatter
    def call(severity, datetime, progname, msg)
      "*** #{msg}\n"
    end
  end
end
