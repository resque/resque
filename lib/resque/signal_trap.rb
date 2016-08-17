require 'thread'

class Resque::SignalTrap
  attr_reader :thread

  def initialize
    @handlers = {}
    @self_read, @self_write = IO.pipe
    @thread = Thread.new(&method(:handle_signal))
  end

  def trap(sig, &block)
    # normalize signal names
    sig = sig.to_s.upcase
    if sig[0,3] == "SIG"
      sig = sig[3..-1]
    end

    @handlers[sig] = block
    Kernel.trap(sig) { @self_write.puts(sig) }
  end

  private

  def handle_signal
    while readable_io = IO.select([@self_read])
      sig = readable_io.first[0].gets.strip
      @handlers[sig].call
    end
  end
end
