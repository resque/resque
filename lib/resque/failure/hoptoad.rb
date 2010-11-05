module Resque
  module Failure
    class Hoptoad < Base
      def self.url
        "http://hoptoadapp.com"
      end
      def save
        ::HoptoadNotifier.notify_or_ignore exception
      end
    end
  end
end
