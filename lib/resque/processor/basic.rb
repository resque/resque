module Resque
  module Processor
    class Basic

      def initialize(worker)
        @worker = worker
      end

      def logger
        @worker.logger
      end

      def process_job(job, &block)
        @worker.perform(job, &block)
      end

      def halt_processing
        #TODO: test this code path?
      end

    end
  end
end
