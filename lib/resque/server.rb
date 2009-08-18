require 'sinatra/base'
require 'erb'
require 'resque'

module Resque
  class Server < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"
    set :public, "#{dir}/server/public"
    set :static, true

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def current_section
        request.path_info.sub('/','').split('/')[0].downcase
      end

      def current_page
        request.path_info.sub('/','').downcase
      end

      def class_if_current(page = '')
        'class="current"' if current_page.include? page.to_s
      end

      def tab(name)
        dname = name.to_s.downcase
        "<li #{class_if_current(dname)}><a href='/#{dname}'>#{name}</a></li>"
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
        end
      end

      def redis_get_value_as_array(key)
        case Resque.redis.type(key)
        when 'none'
          []
        when 'list'
          Resque.redis.lrange(key, 0, 20)
        when 'set'
          Resque.redis.smembers(key)
        when 'string'
          [Resque.redis.get(key)]
        end
      end

      def partial?
        @partial
      end

      def partial(template, local_vars = {})
        @partial = true
        erb(template.to_sym, {:layout => false}, local_vars)
      ensure
        @partial = false
      end
    end

    # to make things easier on ourselves
    get "/" do
      redirect '/overview'
    end

    %w( overview failed queues working workers key ).each do |page|
      get "/#{page}" do
        erb page.to_sym, {}, :resque => Resque
      end

      get "/#{page}/:id" do
        erb page.to_sym, {}, :resque => Resque
      end
    end

    get "/stats" do
      redirect "/stats/resque"
    end

    get "/stats/:id" do
      erb :stats, {}, :resque => Resque
    end

    get "/stats/keys/:key" do
      erb :stats, {}, :resque => Resque
    end

    def self.start(host = 'localhost', port = 4567)
      run! :host => host, :port => port
    end

    def resque
      Resque
    end
  end
end
