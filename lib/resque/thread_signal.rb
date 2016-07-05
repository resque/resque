class Resque::ThreadSignal
  if RUBY_VERSION <= "1.9"
    def initialize
      @signaled = false
    end

    def signal
      @signaled = true
    end

    def wait_for_signal(timeout)
      (10 * timeout).times do
        sleep(0.1)
        return true if @signaled
      end

      @signaled
    end

  else
    def initialize
      @mutex = Mutex.new
      @signaled = false
      @received = ConditionVariable.new
    end

    def signal
      @mutex.synchronize do
        @signaled = true
        @received.signal
      end
    end

    def wait_for_signal(timeout)
      @mutex.synchronize do
        unless @signaled
          @received.wait(@mutex, timeout)
        end

        @signaled
      end
    end

  end
end
