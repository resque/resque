module Resque
  module Failure
    class Ratchetio < Base
      def save
        ::Ratchetio.report_exception(exception, payload)
      end
    end
  end
end
