module Resque
  # A collection of options for Resque
  # @todo reconcile with Resque::Config (issue #1080)
  class Options
    # @param options [Hash<#to_sym,Object>]
    def initialize(options, resque)
      @options = default_options.merge(options.symbolize_keys)
      @resque = resque
    end

    # @param val [Symbol]
    # @return [Object]
    def [](val)
      @options[val]
    end

    # @param val [Symbol]
    # @return [Object]
    def delete(val)
      @options.delete(val)
    end

    # @param val [Symbol]
    # @yield - if no value found at key, returns the result
    #          of evaluating the block instead.
    # @return [Object]
    def fetch(val, &block)
      @options.fetch(val, &block)
    end

    # @return [Boolean]
    def fork_per_job
      self[:fork_per_job]
    end

    # @return [Hash<#to_sym,Object>]
    def to_hash
      @options
    end

  private

    # @param [Hash<#to_sym,Object>]
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
        :fork_per_job => true,
        # When set to true, forked workers will exit with `exit`, calling any `at_exit` code handlers that have been
        # registered in the application. Otherwise, forked workers exit with `exit!`
        :run_at_exit_hooks => false,
        # the logger we're going to use.
        :logger => @resque.logger,
      }
    end

  end
end
