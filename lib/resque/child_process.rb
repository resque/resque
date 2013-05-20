require 'resque/worker_hooks'

module Resque
  # A child process processes a single job. It is created by a Resque Worker.
  class ChildProcess

    attr_reader :worker
    attr_reader :pid
    attr_reader :worker_hooks

    def initialize(worker)
      @worker = worker
      @worker_hooks = WorkerHooks.new(logger)
    end

    def child_job(job, &block)
      reconnect
      worker_hooks.run_hook :after_fork, job
      unregister_signal_handlers
      worker.perform(job, &block)
      exit! unless worker.options[:run_at_exit_hooks]
    end

    def fork_and_perform(job, &block)
      @pid = fork(job) do
        child_job(job, &block)
      end

      if @pid
        wait
        job.fail(DirtyExit.new($?.to_s)) if $?.signaled?
      else
        worker.perform(job, &block)
      end
    end

    def fork(job, &block)
      return unless will_fork?

      worker_hooks.run_hook :before_fork, job
      Kernel.fork(&block)
    end

    # We cannot simply move this method out of the worker
    # without breaking the legacy tests (which are stubbing 
    # the will_fork? method)
    def will_fork?
      worker.will_fork?
    end

    def reconnect
      worker.client.reconnect
    end

    def unregister_signal_handlers
      trap('TERM') { raise TermException.new("SIGTERM") }
      trap('INT', 'DEFAULT')

      begin
        trap('QUIT', 'DEFAULT')
        trap('USR1', 'DEFAULT')
        trap('USR2', 'DEFAULT')
      rescue ArgumentError
      end
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait 5 seconds, and then a KILL signal if it has not quit
    def kill
      return unless pid

      if Process.waitpid(pid, Process::WNOHANG)
        logger.debug "Child #{pid} already quit."
        return
      end

      signal_child("TERM", pid)
      signal_child("KILL", pid) unless quit_gracefully?(pid)
    rescue SystemCallError
      logger.debug "Child #{pid} already quit and reaped."
    end

    # send a signal to a child, have it logged.
    def signal_child(signal, child)
      logger.debug "Sending #{signal} signal to child #{child}"
      Process.kill(signal, child)
    end

    # has our child quit gracefully within the timeout limit?
    def quit_gracefully?(child)
      (worker.options[:timeout].to_f * 10).round.times do |i|
        sleep(0.1)
        return true if Process.waitpid(child, Process::WNOHANG)
      end

      false
    end

    def wait
      srand # Reseeding
      procline "Forked #{pid} at #{Time.now.to_i}"
      begin
        Process.waitpid(pid)
      rescue SystemCallError
        nil
      end
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   resque-VERSION: STRING
    #
    # TODO: This is a duplication of Rescue::Worker#procline
    # which is a protected method. Can we DRY this up?
    def procline(string)
      $0 = "resque-#{Resque::Version}: #{string}"
      logger.debug $0
    end

    def logger
      worker.logger
    end
  end
end
