module Resque
  module Failure
    module Each
      def each(offset = 0, limit = self.count, queue = :failed, class_name = nil)
        # Ensure items is always a list, which is especially important when
        # just a single failure is returned. One would think #all should
        # always be returning a list but at this time, it does not in the
        # case of only a single failure.
        # See https://github.com/resque/resque/pull/916 for more history/context
        items = [all(offset, limit, queue)].flatten
        items.each_with_index do |item, i|
          if !class_name || (item['payload'] && item['payload']['class'] == class_name)
            yield offset + i, item
          end
        end
      end
    end
  end
end
