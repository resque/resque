module Resque
  module Views
    class Layout < Mustache
      include Server::Helpers

      attr_reader :params, :request

      def subtabs
        []
      end

      def tabs
        super.map do |tab_name|
          { :tab => tab(tab_name) }
        end
      end

      def custom_namespace?
        namespace != :resque
      end

      def namespace
        Resque.redis.namespace
      end

      def version
        Resque::Version
      end

      def redis_server
        Resque.redis_id
      end

      def resque
        Resque
      end

      def any_subtabs?
        keyed_subtabs.any?
      end

      def keyed_subtabs
        Array(subtabs).map do |subtab|
          { :subtab => subtab, :class => class_for_subtab(subtab) }
        end
      end

      def class_for_subtab(subtab)
        class_if_current "#{current_section}/#{subtab}"
      end

      def reset_css
        css :reset
      end

      def style_css
        css :style
      end

      def jquery_js
        js "jquery-1.3.2.min"
      end

      def relatize_js
        js "jquery.relatize_date"
      end

      def ranger_js
        js :ranger
      end

      def css(name)
        '<link href="' + u(name) +
          '.css" media="screen" rel="stylesheet" type="text/css">'
      end

      def js(name)
        '<script src="' + u(name) + '.js" type="text/javascript"></script>'
      end
    end
  end
end