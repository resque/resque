require 'resque/processor/basic'
module Resque
  module Processor
    class Fork < Basic

      def process_job(job, &block)
        fork_for_child(job, &block)
      end

      def fork_for_child(job, &block)
        @child_pid = fork(job) do
          begin
            @worker.reconnect
            @worker.after_fork job
            @worker.perform(job, &block)
            exit! unless @worker.options[:run_at_exit_hooks]
          rescue => e
            #TODO: take out this begin/rescue before merging!
            puts e.inspect
            puts e.backtrace.join("\n")
            raise e
          end
        end

        if @child_pid
          wait_for_child
          job.fail(DirtyExit.new($?.to_s)) if $?.signaled?
        end
      ensure
        @child_pid = nil
      end

      def fork(job, &block)
        @worker.before_fork job
        Kernel.fork(&block)
      end

      def wait_for_child
        srand # Reseeding
        @worker.procline "Forked #{@child_pid} at #{Time.now.to_i}"
        begin
          Process.waitpid(@child_pid)
        rescue SystemCallError
          nil
        end
      end

      def halt_processing
        return unless @child_pid

        if Process.waitpid(@child_pid, Process::WNOHANG)
          logger.debug "Child #{@child_pid} already quit."
          return
        end

        signal_child("TERM", @child_pid)

        signal_child("KILL", @child_pid) unless quit_gracefully?(@child_pid)
      rescue SystemCallError
        logger.debug "Child #{@child_pid} already quit and reaped."
      end

      # send a signal to a child, have it logged.
      def signal_child(signal, child)
        logger.debug "Sending #{signal} signal to child #{child}"
        Process.kill(signal, child)
      end

      def quit_gracefully?(child)
        (@worker.options[:timeout].to_f * 10).round.times do |i|
          sleep(0.1)
          return true if Process.waitpid(child, Process::WNOHANG)
        end

        false
      end

    end
  end
end