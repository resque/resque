require 'sinatra'
require 'erb'
require 'resque'

class Resque
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

      def partial?
        @partial
      end

      def partial(template)
        @partial = true
        erb(template.to_sym, :layout => false)
      ensure
        @partial = false
      end
    end

    # to make things easier on ourselves
    get "/" do |page|
      redirect '/overview'
    end

    %w( overview queues processing workers stats ).each do |page|
      get "/#{page}" do
        erb page.to_sym, {}, :resque => resque
      end

      get "/#{page}/:id" do
        erb page.to_sym, {}, :resque => resque
      end
    end

    def self.start(host = 'localhost', port = 4567)
      run! :host => host, :port => port
    end

    def resque
      @resque ||= Resque.new('localhost:6379')
    end
  end
end
