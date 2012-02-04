module Resque
  module Views
    class Workers < Layout
      include WorkerList
      def worker?
        if id = params[:id]
          Resque::Worker.find(id)
        end
      end

      def worker_not_found?
        params[:id] && !Resque::Worker.find(params[:id])
      end

      def workers
        Resque.workers.sort_by { |w| w.to_s }
      end

      def linked_queues
        links = self[:queues].map do |q|
          %(<a class="queue-tag" href="#{u("/queues/#{q}")}">#{q}</a>)
        end

        links.join('')
      end

      def no_workers?
        workers.empty?
      end

      def not_processing
        !self[:processing]
      end
    end
  end
end