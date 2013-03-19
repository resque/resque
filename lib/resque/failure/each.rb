module Resque
  module Failure
    module Each
      def each(offset = 0, limit = self.count, queue = :failed, class_name = nil)
        items = Array(all(offset, limit, queue))
        items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name)
            yield offset + i, item
          end
        end
      end
    end
  end
end
