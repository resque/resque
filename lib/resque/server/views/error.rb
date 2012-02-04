module Resque
  module Views
    class Error < Layout
      def error
        options[:error]
      end
    end
  end
end