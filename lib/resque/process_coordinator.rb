module Resque
  # An interface for working with Resque Processes on the current machine.
  class ProcessCoordinator
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    # @return [Array<Integer>]
    def worker_pids
      if RUBY_PLATFORM =~ /solaris/
        solaris_worker_pids
      elsif RUBY_PLATFORM =~ /mingw32/ || RUBY_PLATFORM =~ /cygwin/
        windows_worker_pids
      else
        linux_worker_pids
      end
    end

    private

    # Find worker pids - platform independent
    #
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    # @param command [String] the system command to execute and parse
    # @return [Array<Integer>] an array of worker pids
    def get_worker_pids(command)
      active_worker_pids = []

      output = %x[#{command}]  # output format of ps must be ^<PID> <COMMAND WITH ARGS>

      raise 'System call for ps command failed. Please make sure that you have a compatible ps command in the path!' unless $?.success?

      output.split($/).each do |line|
        next unless line =~ /resque/i
        next if line =~ /resque-web/

        active_worker_pids.push line.split(' ')[0]
      end

      active_worker_pids
    end

    # Find Resque worker pids on Windows.
    #
    # Returns an Array of string pids of all the other workers on this
    # machine. Useful when pruning dead workers on startup.
    # @return (see #worker_pids)
    def windows_worker_pids
      lines = `tasklist  /FI "IMAGENAME eq ruby.exe" /FO list`.encode("UTF-8", Encoding.locale_charmap).split($/)

      lines.select! { |line| line =~ /^PID:/}
      lines.collect!{ |line| line.gsub(/PID:\s+/, '') }
    end

    # Find Resque worker pids on Linux and OS X.
    #
    # @return (see #worker_pids)
    def linux_worker_pids
      get_worker_pids('ps -A -o pid,command')
    end

    # Find Resque worker pids on Solaris.
    #
    # @return (see #worker_pids)
    def solaris_worker_pids
      get_worker_pids('ps -A -o pid,args')
    end
  end
end
