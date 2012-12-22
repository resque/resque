# Based on https://gist.github.com/3254712.

begin
  require "honeybadger"
rescue LoadError
  raise "Can't find 'honeybadger' gem. Please add it to your Gemfile or install it."
end

module Resque
  module Failure
    class Honeybadger < Base
      def configure(&block)
        Resque::Failure.backend = self
        ::Honeybadger.configure(&block)
      end

      def count
        # We can't get the total # of errors from Honeybadger so we
        # fake it by asking Resque how many errors it has seen.
        Stat[:failed]
      end

      def save
        ::Honeybadger.notify_or_ignore(exception,
          parameters: {
            payload_class: payload["class"].to_s,
            payload_args:  payload["args"].inspect
          }
        )
      end
    end
  end
end
