class ProcessList

  # Returns an Array of string pids of all the other workers on this
  # machine. Useful when pruning dead workers on startup.
  def self.worker_pids
    if RUBY_PLATFORM =~ /solaris/
      solaris_worker_pids
    elsif RUBY_PLATFORM =~ /mingw32/
      windows_worker_pids
    else
      linux_worker_pids
    end
  end

  # Find Resque worker pids on Windows.
  # Returns an Array of string pids of all the other workers on this
  # machine. Useful when pruning dead workers on startup.
  def self.windows_worker_pids
    `tasklist  /FI "IMAGENAME eq ruby.exe" /FO list`.split($/).select { |line| line =~ /^PID:/}.collect{ |line| line.gsub /PID:\s+/, '' }
  end

  # Find Resque worker pids on Linux and OS X.
  #
  def self.linux_worker_pids
    # plist = Sys::ProcTable.ps.map {|p| "#{p.pid} #{p.comm}" }.join("\n")
    get_worker_pids('ps -A -o pid,command')
    # raise get_worker_pids(plist).inspect
  end

  # Find Resque worker pids on Solaris.
  #
  def self.solaris_worker_pids
    get_worker_pids('ps -A -o pid,args')
  end

  # Find worker pids - platform independent
  #
  # Returns an Array of string pids of all the other workers on this
  def self.get_worker_pids(command)
    active_worker_pids = []
    output = %x[#{command}]  # output format of ps must be ^<PID> <COMMAND WITH ARGS>
    raise 'System call for ps command failed. Please make sure that you have a compatible ps command in the path!' unless $?.success?
    output.split($/).each{|line|
      next unless line =~ /resque/i
      next if line =~ /resque-web/
      active_worker_pids.push line.split(' ')[0]
    }
    active_worker_pids
  end
end
