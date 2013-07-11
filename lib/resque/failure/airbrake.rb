begin
  require 'airbrake'
rescue LoadError
  raise "Can't find 'airbrake' gem. Please add it to your Gemfile or install it."
end

module Resque
  module Failure
    # Failure backend for Airbrake
    class Airbrake < Base
      # @override (see Resque::Failure::Base::count)
      # @param (see Resque::Failure::Base::count)
      # @return (see Resque::Failure::Base::count)
      def self.count(queue = nil, class_name = nil)
        # We can't get the total # of errors from Hoptoad so we fake it
        # by asking Resque how many errors it has seen.
        Stat[:failed]
      end

      # @override (see Resque::Failure::Base#save)
      # @param (see Resque::Failure::Base#save)
      # @return (see Resque::Failure::Base#save)
      def save
        ::Airbrake.notify_or_ignore(exception,
          :parameters => {
            :payload_class => payload['class'].to_s,
            :payload_args => payload['args'].inspect
          },
          :component => 'resque',
          :action => action
        )
      end

      # Returns the payload class's name, underscored.
      # This is used internally by {#save}
      # @return [String]
      # @api private
      def action
        action = payload['class'].to_s
        action = action.underscore if action.respond_to?(:underscore)
        action
      end
    end
  end
end
