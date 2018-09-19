require 'time'

module Resque
  class WorkerThread
    attr_reader :id

    def initialize(id, worker, interval, &block)
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

    def spawn
      Thread.new { work }
    end

    def work
      loop do
        if work_one_job(&block)
          @mutex.synchronize do
            @jobs_processed += 1
          end
        else
          break if interval.zero?
          set_procline_for_threads
          log_with_severity :debug, "Sleeping for #{interval} seconds"
          sleep interval
        end
        @mutex.synchronize do
          break if @jobs_processed >= jobs_per_fork
        end
      end
    end

    def work_one_job(&block)
      return false if worker.paused?
      return false unless @job = reserve

      worker.set_procline_for_threads
      set_worker_payload

      log_with_severity :info, "got: #{@job.inspect}"
      @job.worker = worker

      begin
        @job_thread = Thread.new { perform( &block) }
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

    def set_worker_payload
      data = encode \
        :queue   => @job.queue,
        :run_at  => Time.now.utc.iso8601,
        :payload => @job.payload
      data_store.set_worker_payload(self, data)
    end

    def done_working
      data_store.worker_done_working(self) do
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

