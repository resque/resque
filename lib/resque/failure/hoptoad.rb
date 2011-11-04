begin
  require 'hoptoad_notifier'
rescue LoadError
  raise "Can't find 'hoptoad_notifier' gem. Please add it to your Gemfile or install it."
end

require 'resque/failure/thoughtbot'

module Resque
  module Failure
    # A Failure backend that sends exceptions raised by jobs to Hoptoad.
    #
    # To use it, put this code in an initializer, Rake task, or wherever:
    #
    #   require 'resque/failure/hoptoad'
    #
    #   Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::Hoptoad]
    #   Resque::Failure.backend = Resque::Failure::Multiple
    #
    # Once you've configured resque to use the Hoptoad failure backend,
    # you'll want to setup an initializer to configure the Hoptoad.
    #
    # HoptoadNotifier.configure do |config|
    #   config.api_key = 'your_key_here'
    # end
    # For more information see https://github.com/thoughtbot/hoptoad_notifier
    class Hoptoad < Base
      include Resque::Failure::Thoughtbot

      @klass = ::HoptoadNotifier
    end
  end
end
