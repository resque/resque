module Resque
  class VeryVerboseFormatter
    def call(serverity, datetime, progname, msg)
      time = Time.now.strftime('%H:%M:%S %Y-%m-%d')
      "** [#{time}] #$$: #{msg}\n"
    end
  end
end
