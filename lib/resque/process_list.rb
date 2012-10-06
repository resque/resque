require "sys/proctable"
require "rbconfig"

class ProcessList

  # sys-proctable names of process list
  # platform  pid  realuserid  cmdline
  #
  # sunos     pid  uid         psargs
  # win       pid              cmdline
  # linux     pid  uid         cmdline
  # bsd       pid  ruid        cmdline
  # darwin    pid  ruid        cmdline
  # hpux      pid  uid         cmdline

  # Returns an Array of string pids of all the other workers on this
  # machine. Useful when pruning dead workers on startup.
  def self.worker_pids
    case RbConfig::CONFIG['host_os']
    when /sunos|solaris/i
      solaris_worker_pids
    when /mswin|win32|msdos|cygwin|mingw|windows/i
      windows_worker_pids
    when /linux|hpux/i
      linux_worker_pids
    when /bsd|darwin/i
      bsd_worker_pids
    end
  end

  # Find Resque worker pids on Windows.
  # Returns an Array of string pids of all the other workers on this
  # machine. Useful when pruning dead workers on startup.
  def self.windows_worker_pids
    plist = ps.map {|p| "#{p.pid} #{p.cmdline}" }.join("\n")
    get_worker_pids(plist)
  end

  # Find Resque worker pids on Linux and OS X.
  #
  def self.linux_worker_pids
    plist = ps.select{|p| p.uid == Process.uid }.map {|p| "#{p.pid} #{p.psargs}" }.join("\n")
    get_worker_pids(plist)
  end

  # Find Resque worker pids on Solaris.
  #
  def self.solaris_worker_pids
    plist = ps.select{|p| p.uid == Process.uid }.map {|p| "#{p.pid} #{p.cmdline}" }.join("\n")
    get_worker_pids(plist)
  end

  # Find Resque worker pids on BSD.
  #
  def self.bsd_worker_pids
    plist = ps.select{|p| p.ruid == Process.uid }.map {|p| "#{p.pid} #{p.cmdline}" }.join("\n")
    get_worker_pids(plist)
  end

  # Find worker pids - platform independent
  #
  # Returns an Array of string pids of all the other workers on this
  def self.get_worker_pids(plist)
    active_worker_pids = []
    output = plist
    output.split($/).each{|line|
      next unless line =~ /resque/i
      next if line =~ /resque-web/
      active_worker_pids.push line.split(' ')[0]
    }
    active_worker_pids
  end

  def self.ps
    ::Sys::ProcTable.ps
  end
end
