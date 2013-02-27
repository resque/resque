module Resque
  module Failure
    module Extra
      module MultipleBackend
        # Delegates method calls to first backend that supports them.

        def method_missing(*args, &block)
          suitable_backend_send(*args, &block)
        end

        private
        def suitable_backend_send(meth, *args, &block)
          if backend = classes.find { |backend| backend.respond_to?(meth) }
            backend.send(meth, *args, &block)
          else
            raise NotImplementedError
          end
        end
      end

      def matching_job?(job, opts)
        opts.reject! { |_, v| v.nil? }

        opts.all? { |k, v|
          case k.to_sym
          when :class
            job['payload']['class']
          when :smart
            smart_classify(job)
          else
            job[k.to_s]
          end == v
        }
      end

      # Yields failed jobs matching specific conditions,
      # and their index position inside redis list
      #
      # opts is a hash used to match the specific job
      # all opts values should match for the job to be
      # returned.
      def _each_with_index(opts={})
        batch = opts.delete(:batch) || 20
        skip = opts.delete(:skip) || 0 # jobs to skip
        start = 0
        while (failures = self.all(start, batch)).any?
          failures.each_with_index { |job, idx|
            if matching_job?(job, opts)
              if skip > 0
                skip -= 1
              else
                yield(job, start + idx)
              end
            end
          } # failures

          start += batch
        end # while
      end

      def each(*args,&block)
        enum_for(:_each_with_index, *args).each(&block)
      end

      # Delete failed jobs matching specific predicates
      # opts['action'] = :requeue || :mark_for_remove || :requeue_and_remove
      def action_by(opts={}, &block)
        action = opts.delete(:action).to_sym || :requeue
        arg = opts.delete(:arg)
        count = 0
        each(opts) { |job, idx|
          # TODO removeme
          fetched = Resque.decode(Resque.redis.lindex('failed', idx))
          raise "not-equal" if job != fetched

          self.send(action, idx, arg)
          $stdout.puts [action, idx].inspect
          count += 1
        }

        # We can now delete all marked for delete items
        Resque.redis.lrem(:failed, 0, 'marked_for_remove')

        $stdout.puts [:count, count].inspect
        count
      end

      # requeue re-adds the job to the failed jobs with a retried-at attribute
      # This is slow for large jobs, this function skips this step
      def fast_requeue(index, queue=nil)
        item = all(index)
        queue ||= item['queue']
        Job.create(queue, item['payload']['class'], *item['payload']['args'])
      end

      def mark_for_remove(index, _=nil)
        Resque.redis.lset(:failed, index, 'marked_for_remove')
      end

      def requeue_and_remove(index, queue=nil)
        fast_requeue(index, queue)
        mark_for_remove(index)
      end

      def smart_classify(job)
        klass = job['payload']['class']
        args = job['payload']['args']

        if klass =~ /Mailer$/
          args.first
        elsif args.first == 'instance_perform' # [instance_perform, id, method, ....]
          args[2] #method name
        elsif args.first.kind_of?(String)
          args.first
        end
      end

      def stats
        by_class = Hash.new(0)
        by_smart = Hash.new(0)
        by_class_exception = Hash.new(0)

        self.each { |job, _|
          by_class[job['payload']['class']] += 1
          if smart = smart_classify(job)
            class_smart = [job['payload']['class'], smart]
              by_smart[class_smart] += 1
          end
          exception_class = [job['payload']['class'], job['exception']]
          by_class_exception[exception_class] += 1
        }

        # Sort Stats
        by_class = by_class.sort_by(&:last).reverse
        by_smart = by_smart.sort_by(&:last).reverse
        by_class_exception = by_class_exception.sort_by(&:last).reverse

        {
          "class" => by_class,
          "class_smart" => by_smart,
          "class_exception" => by_class_exception
        }
      end

    end
  end
end
