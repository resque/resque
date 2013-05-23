require 'resque/child_processor/basic'

module Resque
  module ChildProcessor
    class Fork < Basic

      attr_reader :pid

      def child_job(job, &block)
        reconnect
        worker_hooks.run_hook :after_fork, job
        unregister_signal_handlers
        worker.perform(job, &block)
        exit! unless worker.options[:run_at_exit_hooks]
      end

      def perform(job, &block)
        @pid = fork(job) do
          child_job(job, &block)
        end

        if @pid
          wait
          job.fail(DirtyExit.new($?.to_s)) if $?.signaled?
        end
      end

      def fork(job, &block)
        worker_hooks.run_hook :before_fork, job
        Kernel.fork(&block)
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

    end
  end
end