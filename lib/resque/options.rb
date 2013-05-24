require 'resque/child_processor/basic'
require 'resque/child_processor/fork'

module Resque
  class Options

    def initialize(options)
      @options = default_options.merge(options.symbolize_keys)
      if options.has_key?(:fork_per_job)
        @options[:child_processor] = options[:fork_per_job] ? ChildProcessor::Fork : ChildProcessor::Basic
      end
    end

    def [](val)
      @options[val]
    end

    def delete(val)
      @options.delete(val)
    end

    def fetch(val, &block)
      @options.fetch(val, &block)
    end

    def child_processor
      self[:child_processor]
    end

    def to_hash
      @options
    end

  private

    def default_options
      {
        # Termination timeout
        :timeout => 5,
        # Worker's poll interval
        :interval => 5,
        # Run as deamon
        :daemon => false,
        # Path to file file where worker's pid will be save
        :pid_file => nil,
        # Use fork(2) on performing jobs
        :child_processor => ChildProcessor::Fork,
        # When set to true, forked workers will exit with `exit`, calling any `at_exit` code handlers that have been
        # registered in the application. Otherwise, forked workers exit with `exit!`
        :run_at_exit_hooks => false,
        # the logger we're going to use.
        :logger => Resque.logger,
      }
    end

  end
end