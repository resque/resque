module Resque
  class VerboseFormatter
    def call(serverity, datetime, progname, msg)
      "*** #{msg}"
    end
  end
end
