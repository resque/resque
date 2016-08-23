require 'thread'

class Resque::SignalHandler
  attr_reader :thread

  def initialize
    @handlers = {}
    reopen
  end

  def reopen
    @self_read.close rescue nil if @self_read
    @self_write.close rescue nil if @self_write
    @thread.kill rescue nil if @thread and @thread.alive?
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
    Kernel.trap(sig) do
      @self_write.puts(sig)
      # Ensure main and `@handlers[sig].call` in handle_signal thread does not run concurrently
      # so that we do not need to care `@handlers[sig].call` is thread-safe
      # But, note that we can not receive same signal again until `@handlers[sig].call` finishes
      Thread.stop
    end
  end

  private

  def handle_signal
    while readable_io = IO.select([@self_read])
      sig = readable_io.first[0].gets.strip
      until Thread.main.stop? do; end
      begin
        @handlers[sig].call
      ensure
        Thread.main.wakeup
      end
    end
  end
end
