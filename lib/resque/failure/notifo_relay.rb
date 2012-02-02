begin
  require 'notifo'
rescue LoadError
  raise "Can't find 'notifo' gem. Please add it to your Gemfile or install it."
end

module Resque
  module Failure
    # A Failure backend that sends exceptions raised by jobs to Notifo.
    #
    # To use it, put this code in an initializer, Rake task, or wherever:
    #
    #   require 'resque/failure/notifo_relay'
    #
    #   Resque::Failure::NotifyRelay.username = 'your_username'
    #   Resque::Failure::NotifyRelay.api_key  = 'your_apikey'
    #   Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::NotifoRelay]
    #   Resque::Failure.backend = Resque::Failure::Multiple
    #
    class NotifoRelay < Base

      class << self
        attr_accessor :username, :api_secret
      end

      def save
        username = NotifoRelay.username
        api_secret = NotifoRelay.api_secret
  
        if username && api_secret
          notifo = Notifo.new(username, api_secret)
          notifo.post(username, "Resque failure: #{exception.class.to_s}")
        end
      end
    end
  end
end
