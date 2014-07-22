require 'resque/worker_hooks'
require 'resque/signal_trapper'
require 'time' # Time#iso8601

module Resque
  # A child process processes a single job. It is created by a Resque Worker.
  class ChildProcess

    attr_reader :worker
    attr_reader :pid
    attr_reader :worker_hooks

    # @param worker [Resque::Worker]
    def initialize(worker)
      @worker = worker
      @worker_hooks = WorkerHooks.new(logger)
    end

    # @param job [Resque::Job]
    # @return [void]
    # @yieldparam (see Resque::Worker#perform)
    # @yieldreturn (see Resque::Worker#perform)
    def child_job(job, &block)
      reconnect
      worker_hooks.run_hook :after_fork, job
      unregister_signal_handlers
      worker.perform(job, &block)
      exit! unless worker.options[:run_at_exit_hooks]
    end

    # @param job [Resque::Job]
    # @return [void]
    # @yieldparam (see Resque::Worker#perform)
    # @yieldreturn (see Resque::Worker#perform)
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

    # @param job [Resque::Job]
    # @return [Object] result of the supplied block
    # @yieldparam [Integer,nil] (see Kernel::fork)
    def fork(job, &block)
      return unless worker.options.fork_per_job

      worker_hooks.run_hook :before_fork, job
      Kernel.fork(&block)
    end

    # @return [void]
    def reconnect
      worker.client.reconnect
    end

    # @return [void]
    def unregister_signal_handlers
      SignalTrapper.trap('TERM') { raise TermException.new("SIGTERM") }
      SignalTrapper.trap('INT', 'DEFAULT')

      SignalTrapper.trap_or_warn('QUIT', 'DEFAULT')
      SignalTrapper.trap_or_warn('USR1', 'DEFAULT')
      SignalTrapper.trap_or_warn('USR2', 'DEFAULT')
    end

    # Kills the forked child immediately with minimal remorse. The job it
    # is processing will not be completed. Send the child a TERM signal,
    # wait 5 seconds, and then a KILL signal if it has not quit
    # @return [void]
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
    # @return [void]
    def signal_child(signal, child)
      logger.debug "Sending #{signal} signal to child #{child}"
      Process.kill(signal, child)
    end

    # has our child quit gracefully within the timeout limit?
    # @param child [Integer]
    # @return [Boolean]
    def quit_gracefully?(child)
      (worker.options[:timeout].to_f * 10).round.times do |i|
        sleep(0.1)
        return true if Process.waitpid(child, Process::WNOHANG)
      end

      false
    end

    # @return [Integer] on success
    # @return [nil] on SystemCallError failure
    def wait
      srand # Reseeding
      procline "Forked #{pid} at #{Time.now.iso8601}"
      begin
        Process.waitpid(pid)
      rescue SystemCallError
        nil
      end
    end

    # Given a string, sets the procline ($0) and logs.
    # Procline is always in the format of:
    #   RESQUE_PROCLINE_PREFIXresque-VERSION: STRING
    #
    # TODO: This is a duplication of Rescue::Worker#procline
    # which is a protected method. Can we DRY this up?
    # @param string [String]
    # @return [void]
    def procline(string)
      $0 = "#{ENV['RESQUE_PROCLINE_PREFIX']}resque-#{Resque::Version}: #{string}"
      logger.debug $0
    end

    # @return (see Resque::Worker#logger)
    def logger
      worker.logger
    end
  end
end
