if !defined? ::Airbrake
  begin
    require 'airbrake'
  rescue LoadError
    raise LoadError, "Can't find 'airbrake' gem. Please add it to your " \
      "Gemfile and install it or define an Airbrake top-level constant " \
      "implementing the Airbrake interface."
  end
end

module Resque
  module Failure
    class Airbrake < Base
      def self.configure(&block)
        Resque.logger.warn "This actually sets global Airbrake configuration, " \
          "which is probably not what you want."
        Resque::Failure.backend = self
        ::Airbrake.configure(&block)
      end

      def self.count(queue = nil, class_name = nil)
        # We can't get the total # of errors from Airbrake so we fake it
        # by asking Resque how many errors it has seen.
        Stat[:failed]
      end

      def save
        notify(exception,
          :parameters => {
          :payload_class => payload['class'].to_s,
          :payload_args => payload['args'].inspect
          }
        )
      end

      private

      def notify(exception, options)
        if ::Airbrake.respond_to?(:notify_sync)
          Airbrake.notify_sync(exception, options)
        else
          # Older versions of Airbrake (< 5)
          Airbrake.notify(exception, options)
        end
      end
    end
  end
end
