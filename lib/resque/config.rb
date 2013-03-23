require "ostruct"
require "resque/core_ext/hash"

module Resque
  class Config
    attr_accessor :options

    def initialize(options = {})
      @options = {
        :daemon => env(:background) || false,
        :count => env(:count) || 5,
        :failure_backend => env(:failure_backend) || "redis",
        :fork_per_job => env(:fork_per_job).nil? || env(:fork_per_job) == "true",
        :interval => env(:interval) || 5,
        :pid => env(:pid_file) || nil,
        :queues => (env(:queue) || env(:queues) || "*"),
        :timeout => env(:rescue_term_timeout) || 4.0,
        :requirement => nil
      }.merge!(options.symbolize_keys!)
    end

    def timeout
      @options[:timeout].to_f
    end

    def interval
      @options[:interval].to_i
    end

    def queues
      @options[:queues].to_s.split(',')
    end

    def method_missing(name)
      name = name.to_sym
      if @options.has_key?(name)
        @options[name]
      end
    end

    protected

      def env(key)
        key = key.to_s.upcase
        if ENV.key?(key)
          Kernel.warn "DEPRECATION WARNING: Using ENV variables is deprecated and will be removed in Resque 2.1"
          ENV[key]
        else
          nil
        end
      end
  end
end
