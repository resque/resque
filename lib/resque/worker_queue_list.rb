require 'set'

module Resque
  # An interface for working with specified lists of queues.
  # @todo: [kill all singletons](#1015) WorkerQueueList#search_order ties directly
  #   into the Resque singleton for ::queues
  class WorkerQueueList
    # @return [Array<String>]
    attr_reader :queues

    # @param queues [Array<#to_s>]
    def initialize(queues)
      @queues = Array(queues).map { |queue| queue.to_s.strip }
    end

    # Returns true if this queue list contains no queues.
    # Note: this has nothing to do with the contents of the queues themselves
    # @return [Boolean]
    def empty?
      queues.empty?
    end

    # Returns the number of queues in this queue list, including splat '*' queue.
    # Note: this has nothing to do with the contents of the queues themselves
    # @return [Integer]
    def size
      queues.size
    end

    # Returns the first queue in this list, after applying search_order.
    # @return [String, nil]
    def first
      search_order.first
    end

    # @return [String] comma-separated in-order queues including splat '*' queue
    def to_s
      queues.join(',')
    end

    # Returns a Set instance with the contents of this queue list.
    # Note: Set does not enforce input-ordering in 1.8.x
    # @return [Set<String>]
    def to_set
      queues.to_set
    end

    # Returns true if the queues specified include a splat '*' for all-queues
    # @return [Boolean]
    def all_queues?
      queues.include?("*")
    end

    # Returns a list of queues to use when searching for a job.
    # A splat ("*") means you want every queue (in alpha order) - this
    # can be useful for dynamically adding new queues.
    # High-priority queues can be placed before a splat to ensure execution
    # before all other dynamic queues, and low-priority queues can be placed
    # after a splat to ensure execution after all other dynamic queues.
    #
    # @example
    #   wql = WorkerQueueList.new(%w(high1 high2 * low))
    #   wql.search_order #=> ['high1','high2', 'alpha', 'beta', 'zeta', 'low']
    #
    # @return [Array<String>]
    def search_order
      search_order = queues.map do |queue|
        case queue
        when "*"
          queue
        when /\*/
          glob_match(queue)
        else
          queue
        end
      end
      if wild = search_order.index("*")
        search_order[wild] = (Resque.queues - search_order).sort
      end

      search_order.flatten.uniq
    end

    def glob_match(pattern)
      regex = Regexp.new("^#{pattern.gsub(/\*/, ".*")}$")
      Resque.queues.grep(regex)
    end
  end

end
