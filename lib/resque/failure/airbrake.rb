begin
  require 'airbrake'
rescue LoadError
  raise "Can't find 'airbrake' gem. Please add it to your Gemfile or install it."
end

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
    # you'll want to setup an initializer to configure the Airbrake.
    #
    # Airbrake.configure do |config|
    #   config.api_key = 'your_key_here'
    # end
    #
    # For more information see https://github.com/airbrake/airbrake
    class Airbrake < Base
      attr_accessor :klass

      def self.configure(&block)
        Resque::Failure.backend = self
        ::Airbrake.configure(&block)
      end

      # We can't get the total # of errors from Hoptoad so we fake it
      # by asking Resque how many errors it has seen.
      def self.count
        Stat[:failed]
      end

      def save
        ::Airbrake.notify_or_ignore(exception,
          :parameters => {
            :payload_class => payload['class'].to_s,
            :payload_args => payload['args'].inspect
          }
        )
      end
    end
  end
end
