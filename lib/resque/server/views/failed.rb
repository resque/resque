module Resque
  module Views
    class Failed < Layout
      def initialize
        @index ||= 0
      end
           
      def failed
        Resque::Failure.all(start, 20)
      end
      
      def requeue_all_url
        u 'failed/requeue/all'
      end
      
      def clear_all_url
        u 'failed/clear'
      end
      
      def failed_remove_url
        u "failed/remove/#{@index}"
      end
      
      def worker_url
        u "workers/#{self[:worker]}"
      end
      
      def retry_job_url
        u "failed/requeue/#{@index}"
      end
      
      def remove_failed_job_url
        u "failed/remove/#{@index}"
      end
      
      def worker_name
        self[:worker].split(':')[0...2].join(':')
      end
      
      def payload_class
        self[:payload] ? self[:payload]['class'] : 'nil'
      end
      
      def payload_args
        self[:payload] ? show_args(self[:payload]['args']) : 'nil'
      end
      
      def error_backtrace
        self[:backtrace].join("\n")
      end
      
      def failed?
        !failed.empty?
      end
      
      def failed_at
        Time.parse("#{self[:failed_at]}").strftime(date_format)
      end
      
      def retried_job_at
        Time.parse("#{self[:retried_at]}").strftime(date_format)
      end

      def date_format
        "%Y/%m/%d %T %z"
      end
      
      def index
        @index + start
      end
      
      def next_index
        @index += 1
        nil
      end

      def start
        params[:start].to_i
      end

      def end
        start + 20
      end
      
      def size
        Resque::Failure.count
      end
    end
  end
end