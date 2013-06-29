require 'resque/signal_trapper'
module Resque
  class IOAwaiter
    # block until SIGCONT is received
    # @return [void]
    def await
      rd, wr = IO.pipe
      SignalTrapper.trap('CONT') {
        wr.write 'x'
        wr.close
      }

      rd.read 1
      rd.close

      SignalTrapper.trap('CONT', 'DEFAULT')
    end
  end
end
