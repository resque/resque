module Resque
  module WorkerManager
    class WorkerStatus
      include Resque::WorkerStatMethods

      def initialize(worker_id)
        @host, @pid, queues_raw = worker_id.split(':')
        @queues = queues_raw.split(',')
        @worker_id = worker_id
      end

      def to_s
        @worker_id
      end

      def ==(other)
        to_s == other.to_s
      end

      def data_store
        Resque.data_store
      end

      def unregister_worker(exception = nil)
        data_store.unregister_worker(self) do
          Stat.clear("processed:#{self}")
          Stat.clear("failed:#{self}")
        end
      end
    end

    class WorkerThreadStatus
      attr_reader :worker

      def initialize(worker_thread_id, job = nil)
        @host, @pid, queues_raw, @thread_id = worker_thread_id.split(':')
        @queues = queues_raw.split(',')
        @job = Resque.decode(job) if job
        @worker = WorkerStatus.new(worker_thread_id.split(':')[0..-2].join(":"))
      end

      def ==(other)
        to_s == other.to_s
      end
    end

    def self.all
      data_store.worker_ids.map { |id| WorkerStatus.new(id) }.compact
    end

    def self.all_heartbeats
      data_store.all_heartbeats
    end

    def self.all_workers_with_expired_heartbeats
      workers = all
      heartbeats = all_heartbeats
      now = data_store.server_time

      workers.select { |worker|
        id = worker.to_s
        heartbeat = heartbeats[id]

        if heartbeat
          seconds_since_heartbeat = (now - Time.parse(heartbeat)).to_i
          seconds_since_heartbeat > Resque.prune_interval
        else
          false
        end
      }
    end

    def self.data_store
      Resque.data_store
    end

    def self.exists?(worker_id)
      data_store.worker_exists?(worker_id)
    end

    def self.find(worker_id)
      if exists?(worker_id)
        WorkerStatus.new(worker_id)
      else
        nil
      end
    end

    def self.prune_dead_workers
      return unless data_store.acquire_pruning_dead_worker_lock(self, Resque.heartbeat_interval)
      all_workers_with_expired_heartbeats.each do |worker|
        Logging.log :info, "Pruning dead worker: #{worker}"
        worker.unregister_worker(PruneDeadWorkerDirtyExit.new(worker.to_s))
      end
    end

    def self.threads_working
      workers = all
      return [] unless workers.any?

      data_store.worker_threads_map(workers).map { |key,value|
        value ? WorkerThreadStatus.new(key, value) : nil
      }.compact
    end

    def self.working
      threads_working.map(&:worker).uniq
    end
  end
end
