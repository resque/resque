module Resque
  module Failure
    # A module mixed into Resque::Failure::Base subclasses to provide #each
    module Each
      # @param options [Hash<#to_sym,Object>]         - options to filter failtures to iterator over
      # @option options offset [Integer] (0)          - beginning offset
      # @option options limit [Integer] (#count)      - maximum quantity to loop over
      # @option options queue [#to_s] (:failed)       - the queue to iterate over
      # @option options class_name [String,nil] (nil) - if provided, limit to given class name
      def each(options = {})
        options = default_options.merge(options.symbolize_keys)
        items = all(options[:offset], options[:limit], options[:queue])
        items.each_with_index do |item, i|
          if options[:class_name].nil? ||
            (item['payload'] && item['payload']['class'] == options[:class_name])

            yield options[:offset] + i, item
          end
        end
      end

      private

      def default_options
        {
          :offset => 0,
          :limit => self.count,
          :queue => :failed,
          :class_name => nil
        }
      end
    end
  end
end
