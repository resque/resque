module Resque
  module Views
    class Overview < Layout
      include QueueMethods
      include WorkingMethods
    end
  end
end