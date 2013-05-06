require 'set'

module Resque

  class WorkerQueueList
    attr_reader :queues

    def initialize(queues)
      @queues = (queues.is_a?(Array) ? queues : [queues]).map { |queue| queue.to_s.strip }
    end

    def empty?
      queues.nil? || queues.empty?
    end

    def size
      queues.size
    end

    def first
      search_order.first
    end

    def to_s
      queues.join(',')
    end

    def to_set
      queues.to_set
    end

    def all_queues?
      queues.include?("*")
    end

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues. Low priority queues
    # can be placed after a splat to ensure execution after all other dynamic
    # queues.
    def search_order
      queues.map do |queue|
        if queue == "*"
          (Resque.queues - queues).sort
        else
          queue
        end
      end.flatten.uniq
    end
  end

end
