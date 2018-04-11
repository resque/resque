module Resque
  module Failure
    # A Failure backend that stores exceptions in Redis. Very simple but
    # works out of the box, along with support in the Resque web app.
    class Redis < Base
      class << self
        attr_writer :expire_generation
        attr_accessor :expire_block
        attr_accessor :failure_block
      end

      def data_store
        Resque.data_store
      end

      def self.data_store
        Resque.data_store
      end

      def save
        data = {
          :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
          :payload   => payload,
          :exception => exception.class.to_s,
          :error     => UTF8Util.clean(exception.to_s),
          :backtrace => filter_backtrace(Array(exception.backtrace)),
          :worker    => worker.to_s,
          :queue     => queue
        }

        rdata = Resque.encode(data)
        Resque.redis.rpush(:failed, rdata)

        unless self.class.whitelist.include? data[:exception]
          self.class.failure_block.call(data) if self.class.failure_block
        end

        gen = payload['generation'] || 1
        if gen == self.class.expire_generation
          self.class.expire_block.call(data) if self.class.expire_block
        end
      end

      def self.count(queue = nil, class_name = nil)
        check_queue(queue)

        if class_name
          n = 0
          each(0, count(queue), queue, class_name) { n += 1 } 
          n
        else
          data_store.num_failed
        end
      end

      def self.queues
        data_store.failed_queue_names
      end

      def self.all(offset = 0, limit = 1, queue = nil)
        check_queue(queue)
        Resque.list_range(:failed, offset, limit)
      end

      def self.each(offset = 0, limit = self.count, queue = :failed, class_name = nil, order = 'desc')
        if class_name
          original_limit = limit
          limit = count
        end
        all_items = limit == 1 ? [all(offset,limit,queue)] : Array(all(offset, limit, queue))
        reversed = false
        if order.eql? 'desc'
          all_items.reverse!
          reversed = true
        end
        all_items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name && (original_limit -= 1) >= 0)
            if reversed
              id = (all_items.length - 1) + (offset - i)
            else
              id = offset + i
            end
            yield id, item
          end
        end
      end

      def self.generation(index)
        item = all(index)
        payload = item['payload']
        payload['generation'].to_i || 1
      end

      # clearing the failure queue only removes jobs which have been retried
      # this makes it impossible to lose failing jobs
      def self.clear(queue = nil)
        ulim = Resque::Failure.count - 1
        ulim.downto(0) do |i|
          job = Resque::Failure.all(i)
          has_id = !job['payload']['id'].nil?
          remove(i) if !job['retried_at'].nil? && has_id
        end
      end

      # pass the id along and increment the generation on requeue
      def self.requeue(index, queue = nil)
        check_queue(queue)
        item = all(index)
        item['retried_at'] = Time.now.strftime("%Y/%m/%d %H:%M:%S")
        Resque.redis.lset(:failed, index, Resque.encode(item))

        payload = item['payload']
        id = payload['id'] || Job.new_uuid
        generation = payload['generation'].to_i || 1

        Job.create_extended(item['queue'], payload['class'], id, generation + 1, *payload['args'])
      end

      def self.remove(id, queue = nil)
        check_queue(queue)
        data_store.remove_from_failed_queue(id, queue)
      end

      def self.requeue_queue(queue)
        i = 0
        while job = all(i)
           requeue(i) if job['queue'] == queue
           i += 1
        end
      end

      def self.requeue_all
        while (fdata = Resque.redis.lpop(:failed))
          begin
            data = JSON.load(fdata)
            qdata = JSON.dump(data["payload"])
            queue = data["queue"]
            Resque.redis.rpush("queue:#{queue}", qdata)
            data = fdata = qdata = queue = nil
          rescue Oj::ParseError
            puts "Could not parse job #{num}, removing it"
          rescue => e
            pp {data: data, fdata: fdata, qdata: qdata, queue: queue}
            raise e
          end
        end
      end

      def self.retry_young
        (count - 1).downto(0) do |num|
          if generation(num) < expire_generation
            requeue(num)
            remove(num)
          end
        end
      end

      def self.remove_queue(queue)
        i = 0
        while job = all(i)
          if job['queue'] == queue
            # This will remove the failure from the array so do not increment the index.
            remove(i)
          else
            i += 1
          end
        end
      end

      def self.check_queue(queue)
        raise ArgumentError, "invalid queue: #{queue}" if queue && queue.to_s != "failed"
      end

      def filter_backtrace(backtrace)
        index = backtrace.index { |item| item.include?('/lib/resque/job.rb') }
        backtrace.first(index.to_i)
      end

      def self.configure
        yield self
      end

      def self.on_expire(&block)
        @expire_block = block
      end

      def self.on_failure(&block)
        @failure_block = block
      end

      def self.expire_generation
        @expire_generation ||= 3
      end

      def self.whitelist=(lst)
        @whitelist = lst.map{|x| x.to_s}
      end

      def self.whitelist
        @whitelist || []
      end
    end
  end
end
