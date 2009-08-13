require 'sinatra'
require 'erb'
require 'resque'

class Resque
  class Server < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/views"
    set :public, "#{dir}/public"
    set :static, true

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html
    end

    get '/' do
      resque
      erb :index
    end

    def self.start(host = 'localhost', port = 4567)
      run! :host => host, :port => port
    end

    def resque
      @resque ||= Resque.new('localhost:6379')
    end
  end
end
