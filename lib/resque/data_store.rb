module Resque
  # An interface between Resque's persistence and the actual
  # implementation.
  class DataStore
    extend Forwardable

    HEARTBEAT_KEY = "workers:heartbeat"

    def initialize(redis)
      @redis                = redis
      @queue_access         = QueueAccess.new(@redis)
      @failed_queue_access  = FailedQueueAccess.new(@redis)
      @workers              = Workers.new(@redis)
      @stats_access         = StatsAccess.new(@redis)
    end

    def_delegators :@queue_access, :push_to_queue,
                                   :pop_from_queue,
                                   :queue_size,
                                   :peek_in_queue,
                                   :queue_names,
                                   :remove_queue,
                                   :everything_in_queue,
                                   :remove_from_queue,
                                   :watch_queue,
                                   :list_range

    def_delegators :@failed_queue_access, :add_failed_queue,
                                          :remove_failed_queue,
                                          :num_failed,
                                          :failed_queue_names,
                                          :push_to_failed_queue,
                                          :clear_failed_queue,
                                          :update_item_in_failed_queue,
                                          :remove_from_failed_queue
    def_delegators :@workers, :worker_ids,
                              :workers_map,
                              :get_worker_payload,
                              :worker_exists?,
                              :register_worker,
                              :worker_started,
                              :unregister_worker,
                              :heartbeat,
                              :heartbeat!,
                              :remove_heartbeat,
                              :all_heartbeats,
                              :acquire_pruning_dead_worker_lock,
                              :set_worker_payload,
                              :worker_start_time,
                              :worker_done_working

    def_delegators :@stats_access, :clear_stat,
                                   :decrement_stat,
                                   :increment_stat,
                                   :stat

    def decremet_stat(*args)
      warn '[Resque] [Deprecation] Resque::DataStore #decremet_stat method is deprecated (please use #decrement_stat)'
      decrement_stat(*args)
    end

    # Compatibility with any non-Resque classes that were using Resque.redis as a way to access Redis
    def method_missing(sym,*args,&block)
      # TODO: deprecation warning?
      @redis.send(sym,*args,&block)
    end

    # make use respond like redis
    def respond_to?(method,include_all=false)
      @redis.respond_to?(method,include_all) || super
    end

    # Get a string identifying the underlying server.
    # Probably should be private, but was public so must stay public
    def identifier
      @redis.inspect
    end

    # Force a reconnect to Redis without closing the connection in the parent
    # process after a fork.
    def reconnect
      @redis._client.connect
    end

    # Returns an array of all known Resque keys in Redis. Redis' KEYS operation
    # is O(N) for the keyspace, so be careful - this can be slow for big databases.
    def all_resque_keys
      @redis.keys("*").map do |key|
        key.sub("#{@redis.namespace}:", '')
      end
    end

    def server_time
      time, _ = @redis.time
      Time.at(time)
    end

    class QueueAccess
      def initialize(redis)
        @redis = redis
      end
      def push_to_queue(queue,encoded_item)
        @redis.pipelined do |piped|
          watch_queue(queue, redis: piped)
          piped.rpush redis_key_for_queue(queue), encoded_item
        end
      end

      # Pop whatever is on queue
      def pop_from_queue(queue)
        @redis.lpop(redis_key_for_queue(queue))
      end

      # Get the number of items in the queue
      def queue_size(queue)
        @redis.llen(redis_key_for_queue(queue)).to_i
      end

      # Examine items in the queue.
      #
      # NOTE: if count is 1, you will get back an object, otherwise you will
      #       get an Array.  I'm not making this up.
      def peek_in_queue(queue, start = 0, count = 1)
        list_range(redis_key_for_queue(queue), start, count)
      end

      def queue_names
        Array(@redis.smembers(:queues))
      end

      def remove_queue(queue)
        @redis.pipelined do |piped|
          piped.srem(:queues, queue.to_s)
          piped.del(redis_key_for_queue(queue))
        end
      end

      def everything_in_queue(queue)
        @redis.lrange(redis_key_for_queue(queue), 0, -1)
      end

      # Remove data from the queue, if it's there, returning the number of removed elements
      def remove_from_queue(queue,data)
        @redis.lrem(redis_key_for_queue(queue), 0, data)
      end

      # Private: do not call
      def watch_queue(queue, redis: @redis)
        redis.sadd(:queues, queue.to_s)
      end

      # Private: do not call
      def list_range(key, start = 0, count = 1)
        if count == 1
          @redis.lindex(key, start)
        else
          Array(@redis.lrange(key, start, start+count-1))
        end
      end

    private

      def redis_key_for_queue(queue)
        "queue:#{queue}"
      end

    end

    class FailedQueueAccess
      def initialize(redis)
        @redis = redis
      end

      def add_failed_queue(failed_queue_name)
        @redis.sadd(:failed_queues, failed_queue_name)
      end

      def remove_failed_queue(failed_queue_name=:failed)
        @redis.del(failed_queue_name)
      end

      def num_failed(failed_queue_name=:failed)
        @redis.llen(failed_queue_name).to_i
      end

      def failed_queue_names(find_queue_names_in_key=nil)
        if find_queue_names_in_key.nil?
          [:failed]
        else
          Array(@redis.smembers(find_queue_names_in_key))
        end
      end

      def push_to_failed_queue(data,failed_queue_name=:failed)
        @redis.rpush(failed_queue_name,data)
      end

      def clear_failed_queue(failed_queue_name=:failed)
        @redis.del(failed_queue_name)
      end

      def update_item_in_failed_queue(index_in_failed_queue,new_item_data,failed_queue_name=:failed)
        @redis.lset(failed_queue_name, index_in_failed_queue, new_item_data)
      end

      def remove_from_failed_queue(index_in_failed_queue,failed_queue_name=nil)
        failed_queue_name ||= :failed
        hopefully_unique_value_we_can_use_to_delete_job = ""
        @redis.lset(failed_queue_name, index_in_failed_queue, hopefully_unique_value_we_can_use_to_delete_job)
        @redis.lrem(failed_queue_name, 1,                     hopefully_unique_value_we_can_use_to_delete_job)
      end
    end

    class Workers
      def initialize(redis)
        @redis = redis
      end

      def worker_ids
        Array(@redis.smembers(:workers))
      end

      # Given a list of worker ids, returns a map of those ids to the worker's value
      # in redis, even if that value maps to nil
      def workers_map(worker_ids)
        redis_keys = worker_ids.map { |id| "worker:#{id}" }
        @redis.mapped_mget(*redis_keys)
      end

      # return the worker's payload i.e. job
      def get_worker_payload(worker_id)
        @redis.get("worker:#{worker_id}")
      end

      def worker_exists?(worker_id)
        @redis.sismember(:workers, worker_id)
      end

      def register_worker(worker)
        @redis.pipelined do |piped|
          piped.sadd(:workers, worker)
          worker_started(worker, redis: piped)
        end
      end

      def worker_started(worker, redis: @redis)
        redis.set(redis_key_for_worker_start_time(worker), Time.now.to_s)
      end

      def unregister_worker(worker, &block)
        @redis.pipelined do |piped|
          piped.srem(:workers, worker)
          piped.del(redis_key_for_worker(worker))
          piped.del(redis_key_for_worker_start_time(worker))
          piped.hdel(HEARTBEAT_KEY, worker.to_s)

          block.call redis: piped
        end
      end

      def remove_heartbeat(worker)
        @redis.hdel(HEARTBEAT_KEY, worker.to_s)
      end

      def heartbeat(worker)
        heartbeat = @redis.hget(HEARTBEAT_KEY, worker.to_s)
        heartbeat && Time.parse(heartbeat)
      end

      def heartbeat!(worker, time)
        @redis.hset(HEARTBEAT_KEY, worker.to_s, time.iso8601)
      end

      def all_heartbeats
        @redis.hgetall(HEARTBEAT_KEY)
      end

      def acquire_pruning_dead_worker_lock(worker, expiry)
        @redis.set(redis_key_for_worker_pruning, worker.to_s, :ex => expiry, :nx => true)
      end

      def set_worker_payload(worker, data)
        @redis.set(redis_key_for_worker(worker), data)
      end

      def worker_start_time(worker)
        @redis.get(redis_key_for_worker_start_time(worker))
      end

      def worker_done_working(worker, &block)
        @redis.pipelined do |piped|
          piped.del(redis_key_for_worker(worker))
          block.call redis: piped
        end
      end

    private

      def redis_key_for_worker(worker)
        "worker:#{worker}"
      end

      def redis_key_for_worker_start_time(worker)
        "#{redis_key_for_worker(worker)}:started"
      end

      def redis_key_for_worker_pruning
        "pruning_dead_workers_in_progress"
      end
    end

    class StatsAccess
      def initialize(redis)
        @redis = redis
      end
      def stat(stat)
        @redis.get("stat:#{stat}").to_i
      end

      def increment_stat(stat, by = 1, redis: @redis)
        redis.incrby("stat:#{stat}", by)
      end

      def decremet_stat(stat, by = 1)
        @redis.decrby("stat:#{stat}", by)
      end

      def clear_stat(stat, redis: @redis)
        redis.del("stat:#{stat}")
      end
    end
  end
end
