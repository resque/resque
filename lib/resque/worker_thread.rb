module Resque
  class WorkerThread
    attr_reader :id, :worker, :interval
    attr_accessor :job

    def initialize(worker, id = 0, interval = 0, &block)
      @id = id
      @worker = worker
      @interval = interval
      @block = block
    end

    def to_s
      "#{worker}:#{@id}"
    end

    def data_store
      worker.data_store
    end

    def jobs_per_fork
      @jobs_per_fork ||= worker.jobs_per_fork
    end

    def log_with_severity(severity, message)
      worker.log_with_severity(severity, "[Thread #{@id}] #{message}")
    end

    def payload_class_name
      @job&.payload_class_name
    end

    def spawn
      Thread.new { work }
    end

    def work
      loop do
        if work_one_job(&@block)
          worker.job_processed
        else
          break if interval.zero?
          worker.set_procline
          log_with_severity :debug, "Sleeping for #{interval} seconds"
          sleep interval
        end
        break if worker.jobs_processed >= jobs_per_fork
      end
    end

    def work_one_job(&block)
      return false if worker.paused?
      return false unless @job = worker.reserve

      worker.set_procline
      set_payload

      log_with_severity :info, "got: #{@job.inspect}"
      @job.worker = worker

      begin
        @job_thread = Thread.new { perform(&block) }
        @job_thread.join
        @job_thread = nil
      rescue Object => e
        report_failed_job(e)
      end

      done_working

      true
    end

    def perform
      begin
        @job.perform
      rescue Object => e
        report_failed_job(e)
      else
        log_with_severity :info, "done: #{@job.inspect}"
      ensure
        yield @job if block_given?
      end
    end

    def set_payload
      data = worker.encode \
        :queue   => @job.queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => @job.payload
      data_store.set_worker_thread_payload(self, data)
    end

    def done_working
      data_store.worker_thread_done_working(self) do
        worker.processed!
      end
    end

    def report_failed_job(exception)
      log_with_severity :error, "#{@job.inspect} failed: #{exception.inspect}"
      begin
        @job.fail(exception)
      rescue Object => exception
        log_with_severity :error, "Received exception when reporting failure: #{exception.inspect}"
      end
      begin
        failed!
      rescue Object => exception
        log_with_severity :error, "Received exception when increasing failed jobs counter (redis issue) : #{exception.inspect}"
      end
    end
  end
end

