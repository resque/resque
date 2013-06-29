module Resque
  # Helper for trapping signals.
  #
  #   Trap a signal (accepts same params as Signal#trap):
  #     SignalTrapper.trap('INT') { do_stuff }
  #   Trap a signal, but don't raise exception if unsupported signal:
  #     SignalTrapper.trap_or_warn('INT') { do_stuff }
  module SignalTrapper
    # A wrapper around Signal::trap
    # @see Signal::trap
    def self.trap(*args, &block)
      Signal.trap(*args, &block)
    end

    # Trap a signal, but don't raise exception if unsupported signal:
    # @see Signal::trap
    # @return [void]
    def self.trap_or_warn(*args, &block)
      trap(*args, &block)
    rescue ArgumentError => e
      warn e
    end
  end
end
