require 'thread'

class Resque::SignalHandler
  def initialize
    @handlers = {}
    @self_read, @self_write = IO.pipe
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

  def handle_signal(timeout)
    if readable_io = IO.select([@self_read], nil, nil, timeout)
      sig = readable_io.first[0].gets.strip
      @handlers[sig].call
    end
  end
end
