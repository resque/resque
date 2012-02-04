module Resque
  class Server < Sinatra::Base
    module Helpers
      include Rack::Utils
      alias_method :h, :escape_html

      def current_section
        url_path request.path_info.sub('/','').split('/')[0].downcase
      end

      def current_page
        url_path request.path_info.sub('/','')
      end

      def url_path(*path_parts)
        [ path_prefix, path_parts ].join("/").squeeze('/')
      end
      alias_method :u, :url_path

      def path_prefix
        request.env['SCRIPT_NAME']
      end

      def class_if_current(path = '')
        'class="current"' if current_page[0, path.size] == path
      end

      def tab(name)
        dname = name.to_s.downcase
        path = url_path(dname)
        "<li #{class_if_current(path)}><a href='#{path}'>#{name}</a></li>"
      end

      def tabs
        Resque::Server.tabs
      end

      def redis_get_size(key)
        case Resque.redis.type(key)
        when 'none'
          []
        when 'list'
          Resque.redis.llen(key)
        when 'set'
          Resque.redis.scard(key)
        when 'string'
          Resque.redis.get(key).length
        when 'zset'
          Resque.redis.zcard(key)
        end
      end

      def redis_get_value_as_array(key, start=0)
        case Resque.redis.type(key)
        when 'none'
          []
        when 'list'
          Resque.redis.lrange(key, start, start + 20)
        when 'set'
          Resque.redis.smembers(key)[start..(start + 20)]
        when 'string'
          [Resque.redis.get(key)]
        when 'zset'
          Resque.redis.zrange(key, start, start + 20)
        end
      end

      def show_args(args)
        Array(args).map { |a| a.inspect }.join("\n")
      end

      def worker_hosts
        @worker_hosts ||= worker_hosts!
      end

      def worker_hosts!
        hosts = Hash.new { [] }

        Resque.workers.each do |worker|
          host, _ = worker.to_s.split(':')
          hosts[host] += [worker.to_s]
        end

        hosts
      end

      def partial?
        @partial
      end

      def poll
        if @polling
          text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
        else
          text = "<a href='#{u(request.path_info)}.poll' rel='poll'>Live Poll</a>"
        end
        "<p class='poll'>#{text}</p>"
      end
    end
  end
end