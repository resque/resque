module Resque
  module Views
    class Stats < Layout
      def subtabs
        %w( resque redis keys )
      end

      def redis_server
        Resque.redis_id
      end

      def key_page?
        !!key
      end

      def set_key_page?
        key && SetKeyInfo.new(key, params, request)
      end

      def key
        params[:key]
      end

      def key_type(key = key)
        resque.redis.type(key)
      end

      def key_size(key = key)
        redis_get_size(key)
      end

      def key_value_as_array(key = key)
        redis_get_value_as_array(key)
      end

      def partial(name)
        respond_to?(name) ? send(name) : super
      end

      def key_string_or_sets
        type = Resque.redis.type(params[:key]) == "string"
        partial(type ? :key_string : :key_sets)
      end

      def keys_page?
        params[:id] == "keys"
      end

      def keys
        Resque.keys.sort.map do |key|
          hash = {}
          hash[:name] = key
          hash[:href] = u("/stats/keys/#{key}")
          hash[:type] = key_type(key)
          hash[:size] = key_size(key)
          hash
        end
      end

      def resque_page?
        ResqueInfo.new if params[:id] == "resque"
      end

      def redis_page?
        RedisInfo.new if params[:id] == "redis"
      end

      class ResqueInfo
        def stats
          Resque.info.to_a.sort_by { |i| i[0].to_s }.map do |key, value|
            { :key => key, :value => value }
          end
        end
      end

      class RedisInfo
        def stats
          Resque.redis.info.to_a.sort_by { |i| i[0].to_s }.map do |key, value|
            { :key => key, :value => value }
          end
        end
      end

      class SetKeyInfo
        include Server::Helpers

        attr_reader :key, :params, :request
        def initialize(key, params, request)
          @key = key
          @params = params
          @request = request
        end

        def start
          params[:start].to_i
        end

        def end
          start + 20
        end

        def size
          redis_get_size(key)
        end

        def pagination?
          less_page? || more_page?
        end

        def less_page?
          start - 20 >= 0
        end

        def more_page?
          start + 20 <= size
        end

        def start_less
          start - 20
        end

        def start_more
          start + 20
        end

        def key_as_array
          redis_get_value_as_array(key, start).map do |item|
            { :row => item }
          end
        end
      end
    end
  end
end