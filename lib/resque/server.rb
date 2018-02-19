require 'sinatra/base'
require 'tilt/erb'
require 'resque'
require 'resque/version'
require 'time'
require 'yaml'

if defined?(Encoding) && Encoding.default_external != Encoding::UTF_8
  Encoding.default_external = Encoding::UTF_8
end

module Resque
  class Server < Sinatra::Base
    require 'resque/server/helpers'

    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"

    if respond_to? :public_folder
      set :public_folder, "#{dir}/server/public"
    else
      set :public, "#{dir}/server/public"
    end

    set :static, true

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def current_section
        url_path request.path_info.sub('/','').split('/')[0].downcase
      end

      def current_page
        url_path request.path_info.sub('/','')
      end

      def url_path(*path_parts)
        [ url_prefix, path_prefix, path_parts ].join("/").squeeze('/')
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

      def url_prefix
        Resque::Server.url_prefix
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
        Array(args).map do |a|
          a.to_yaml
        end.join("\n")
      rescue
        args.to_s
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

      def partial(template, local_vars = {})
        @partial = true
        erb(template.to_sym, {:layout => false}, local_vars)
      ensure
        @partial = false
      end

      def poll
        if defined?(@polling) && @polling
          text = "Last Updated: #{Time.now.strftime("%H:%M:%S")}"
        else
          text = "<a href='#{u(request.path_info)}.poll' rel='poll'>Live Poll</a>"
        end
        "<p class='poll'>#{text}</p>"
      end

    end

    def show(page, layout = true)
      response["Cache-Control"] = "max-age=0, private, must-revalidate"
      begin
        erb page.to_sym, {:layout => layout}, :resque => Resque
      rescue Errno::ECONNREFUSED
        erb :error, {:layout => false}, :error => "Can't connect to Redis! (#{Resque.redis_id})"
      end
    end

    def show_for_polling(page)
      content_type "text/html"
      @polling = true
      show(page.to_sym, false).gsub(/\s{1,}/, ' ')
    end

    # to make things easier on ourselves
    get "/?" do
      redirect url_path(:overview)
    end

    %w( overview workers ).each do |page|
      get "/#{page}.poll/?" do
        show_for_polling(page)
      end

      get "/#{page}/:id.poll/?" do
        show_for_polling(page)
      end
    end

    %w( overview queues working workers key ).each do |page|
      get "/#{page}/?" do
        show page
      end

      get "/#{page}/:id/?" do
        show page
      end
    end

    post "/queues/:id/remove" do
      Resque.remove_queue(params[:id])
      redirect u('queues')
    end

    get "/failed/?" do
      if Resque::Failure.url
        redirect Resque::Failure.url
      else
        show :failed
      end
    end

    get "/failed/:queue" do
      if Resque::Failure.url
        redirect Resque::Failure.url
      else
        show :failed
      end
    end

    post "/failed/clear" do
      Resque::Failure.clear
      redirect u('failed')
    end

    post "/failed/:queue/clear" do
      Resque::Failure.clear params[:queue]
      redirect u('failed')
    end

    post "/failed/requeue/all" do
      Resque::Failure.requeue_all
      redirect u('failed')
    end

    post "/failed/:queue/requeue/all" do
      Resque::Failure.requeue_queue Resque::Failure.job_queue_name(params[:queue])
      redirect url_path("/failed/#{params[:queue]}")
    end

    get "/failed/requeue/:index/?" do
      Resque::Failure.requeue(params[:index])
      if request.xhr?
        return Resque::Failure.all(params[:index])['retried_at']
      else
        redirect u('failed')
      end
    end

    get "/failed/:queue/requeue/:index/?" do
      Resque::Failure.requeue(params[:index], params[:queue])
      if request.xhr?
        return Resque::Failure.all(params[:index],1,params[:queue])['retried_at']
      else
        redirect url_path("/failed/#{params[:queue]}")
      end
    end

    get "/failed/remove/:index/?" do
      Resque::Failure.remove(params[:index])
      redirect u('failed')
    end

    get "/failed/:queue/remove/:index/?" do
      Resque::Failure.remove(params[:index], params[:queue])
      redirect url_path("/failed/#{params[:queue]}")
    end

    get "/stats/?" do
      redirect url_path("/stats/resque")
    end

    get "/stats/:id/?" do
      show :stats
    end

    get "/stats/keys/:key/?" do
      show :stats
    end

    get "/stats.txt/?" do
      info = Resque.info

      stats = []
      stats << "resque.pending=#{info[:pending]}"
      stats << "resque.processed+=#{info[:processed]}"
      stats << "resque.failed+=#{info[:failed]}"
      stats << "resque.workers=#{info[:workers]}"
      stats << "resque.working=#{info[:working]}"

      Resque.queues.each do |queue|
        stats << "queues.#{queue}=#{Resque.size(queue)}"
      end

      content_type 'text/html'
      stats.join "\n"
    end

    def resque
      Resque
    end

    def self.tabs
      @tabs ||= ["Overview", "Working", "Failed", "Queues", "Workers", "Stats"]
    end

    def self.url_prefix=(url_prefix)
      @url_prefix = url_prefix
    end

    def self.url_prefix
      (@url_prefix.nil? || @url_prefix.empty?) ? '' : @url_prefix + '/'
    end
  end
end
