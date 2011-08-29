begin
  require 'hoptoad_notifier'
rescue LoadError
  raise "Can't find 'hoptoad_notifier' gem. Please add it to your Gemfile or install it."
end

require 'resque/failure/thoughtbot'

module Resque
  module Failure
    # Deprecated: A Failure backend that sends exceptions raised by jobs to Hoptoad.
    # Use Resque::Failure::Airbrake instead if possible.
    #
    class Hoptoad < Thoughtbot
      @@klass = ::HoptoadNotifier
    end
  end
end
