require 'resque/signal_trapper'
module Resque
  # A Waiter class that relies on SIGCONT to unblock.
  # The duck-type that Resque::Worker needs as :awaiter
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
