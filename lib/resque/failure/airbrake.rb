begin
  require 'airbrake'
rescue LoadError
  raise "Can't find 'airbrake' gem. Please add it to your Gemfile or install it."
end

require 'resque/failure/thoughtbot'

module Resque
  module Failure
    # A Failure backend that sends exceptions raised by jobs to Airbrake.
    #
    # To use it, put this code in an initializer, Rake task, or wherever:
    #
    #   require 'resque/failure/airbrake'
    #
    #   Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::Airbrake]
    #   Resque::Failure.backend = Resque::Failure::Multiple
    #
    # Once you've configured resque to use the Airbrake failure backend,
    # you'll want to setup an initializer to configure Airbrake.
    #
    # Airbrake.configure do |config|
    #   config.api_key = 'your_key_here'
    # end
    # For more information see https://github.com/thoughtbot/airbrake
    class Airbrake < Thoughtbot
      @@klass = ::Airbrake
    end
  end
end
