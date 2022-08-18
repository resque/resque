# frozen_string_literal: true

module Resque
  class Railtie < Rails::Railtie
    rake_tasks do
      require 'resque/tasks'

      # redefine the task to load the rails env
      task "resque:setup" => :environment
    end

    # Describes the flexible `eager_load` configuration process for Resque when used in a Rails application.
    class EagerLoad
      class << self
        def configuration
          @_configuration ||= Configuration.new
        end

        def configure
          yield(configuration) if block_given?

          configuration
        end
        alias configure_for_environments configure

        def enabled?
          return configuration.enabled if configuration.for_environments.empty?

          validate_environment!

          configuration.for_environments.fetch(current_environment, false)
        end

        def validate_environment!
          return if configuration.for_environments.keys.include?(current_environment)

          raise ::Resque::EagerLoadConfigurationError.new
        end

        def current_environment
          @current_environment ||= ::Resque.info[:environment]
        end
      end

      private_class_method :validate_environment!
      private_class_method :current_environment

      class Configuration
        attr_accessor :enabled

        attr_accessor :environment_configuration
        alias for_environments environment_configuration

        def initialize
          @enabled = false
          @environment_configuration = {}
        end

        private

        def method_missing(symbol, arg)
          string_method_name = symbol.to_s

          if string_method_name.end_with?('=') && (arg.is_a?(TrueClass) || arg.is_a?(FalseClass))
            environment_configuration[string_method_name.chop] = arg
          else
            raise ::Resque::EagerLoadConfigurationError.new
          end
        end

        def respond_to_missing?(_method_name, _include_private = false)
          false
        end
      end
    end
  end
end
