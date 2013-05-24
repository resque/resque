require 'resque/worker_hooks'

module Resque
  module ChildProcessor
    class Basic

      attr_reader :worker
      attr_reader :worker_hooks

      def initialize(worker)
        @worker = worker
        @worker_hooks = WorkerHooks.new(logger)
      end

      def perform(job, &block)
        worker.perform(job, &block)
      end

      def kill
        #no-op
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
end