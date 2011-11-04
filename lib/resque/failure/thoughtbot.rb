module Resque
  module Failure
    module Thoughtbot
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        attr_accessor :klass

        def configure(&block)
          Resque::Failure.backend = self
          klass.configure(&block)
        end

        def count
          # We can't get the total # of errors from Hoptoad so we fake it
          # by asking Resque how many errors it has seen.
          Stat[:failed]
        end
      end

      def save
        self.class.klass.notify_or_ignore(exception,
          :parameters => {
            :payload_class => payload['class'].to_s,
            :payload_args => payload['args'].inspect
          }
        )
      end
    end
  end
end
