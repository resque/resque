module Resque
  module Failure
    # A module mixed into Resque::Failure::Base subclasses to provide #each
    module Each
      # @param offset [Integer] (0)     - beginning offset
      # @param limit [Integer] (#count) - maximum quantity to loop over
      # @param queue [#to_s] (:failed)  - the queue to iterate over
      # @param class_name [String,nil] (nil)  - if provided, limit to given class name
      def each(offset = 0, limit = self.count, queue = :failed, class_name = nil)
        items = all(offset, limit, queue)
        items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name)
            yield offset + i, item
          end
        end
      end
    end
  end
end
