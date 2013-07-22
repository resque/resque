begin
  require 'airbrake'
rescue LoadError
  raise "Can't find 'airbrake' gem. Please add it to your Gemfile or install it."
end

module Resque
  module Failure
    class Airbrake < Base
      def self.configure(&block)
        Resque.logger.warn "This actually sets global Airbrake configuration, " \
          "which is probably not what you want. This will be gone in 2.0."
        Resque::Failure.backend = self
        ::Airbrake.configure(&block)
      end

      def self.count(queue = nil, class_name = nil)
        # We can't get the total # of errors from Airbrake so we fake it
        # by asking Resque how many errors it has seen.
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
