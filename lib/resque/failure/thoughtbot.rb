module Resque
  module Failure
    class Thoughtbot < Base
      @@klass = nil

      def self.configure(&block)
        Resque::Failure.backend = self
        @@klass.configure(&block)
      end

      def self.count
        # We can't get the total # of errors from Airbrake so we fake it
        # by asking Resque how many errors it has seen.
        Stat[:failed]
      end

      def save
        @@klass.notify_or_ignore(exception,
          :parameters => {
            :payload_class => payload['class'].to_s,
            :payload_args => payload['args'].inspect
          }
        )
      end

    end
  end
end
