# frozen_string_literal: true

require 'test_helper'

require 'resque/railtie'

describe Resque::Railtie::EagerLoad do
  before { EagerLoadTestHelper.reset_config! }
  after { ENV['RAILS_ENV'] = nil }

  describe '.enabled?' do
    it 'returns eager load config value set to false by default when configuration has not been set ' do
      refute Resque::Railtie::EagerLoad.enabled?
    end

    it 'returns eager load config value when configuration has been set for all environments' do
      Resque::Railtie::EagerLoad.configure { |configuration| configuration.enabled = true }

      assert Resque::Railtie::EagerLoad.enabled?
    end

    it 'returns eager load config value when configuration has been set for all environments' do
      Resque::Railtie::EagerLoad.configure_for_environments do |environment|
        environment.development = false
        environment.staging = true
        environment.production = true
      end

      refute Resque::Railtie::EagerLoad.enabled?
    end

    it 'returns eager load config value when configuration has been set for all environments' do
      ENV['RAILS_ENV'] = 'staging'

      Resque::Railtie::EagerLoad.configure_for_environments do |environment|
        environment.development = false
        environment.staging = true
        environment.production = true
      end

      assert Resque::Railtie::EagerLoad.enabled?
    end

    it 'returns eager load config value when configuration has been set for all environments' do
      ENV['RAILS_ENV'] = 'production'

      Resque::Railtie::EagerLoad.configure_for_environments do |environment|
        environment.development = true
        environment.staging = false
        environment.production = true
      end

      assert Resque::Railtie::EagerLoad.enabled?

      environment_configuration = { 'development' => true, 'staging' => false, 'production' => true }

      assert_equal environment_configuration, Resque::Railtie::EagerLoad.configuration.for_environments
    end
  end

  describe 'invalid configuration' do
    it 'raises a ConfigurationError with the explanation' do
      Resque::Railtie::EagerLoad.configure_for_environments do |environment|
        environment.invalid = true
      end

      error = _ { Resque::Railtie::EagerLoad.enabled? }.must_raise ::Resque::EagerLoadConfigurationError

      assert_match EagerLoadTestHelper.configuration_error_message, error.message
    end

    it 'raises a ConfigurationError with the explanation when the configuration value for environments is not correct' do
      error = assert_raises ::Resque::EagerLoadConfigurationError do
        Resque::Railtie::EagerLoad.configure_for_environments do |environment|
          environment.development = 'invalid'
        end
      end

      assert_match EagerLoadTestHelper.configuration_error_message, error.message
    end
  end
end
