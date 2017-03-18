module Resque
  module Failure
    class Exceptional < Base
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
          # We can't get the total # of errors from Exceptional so we fake it
          # by asking Resque how many errors it has seen.
          Stat[:failed]
        end
      end

      def save
        ::Exceptional.context(class: payload[:class].to_s, args: payload[:args].inspect)
        ::Exceptional.handle(exception)
      end
    end
  end
end
