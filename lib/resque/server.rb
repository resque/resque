require 'sinatra/base'
require 'tilt/erb'
require 'resque'
require 'resque/server_helper'
require 'resque/version'
require 'time'
require 'yaml'

if defined?(Encoding) && Encoding.default_external != Encoding::UTF_8
  Encoding.default_external = Encoding::UTF_8
end

module Resque
  class Server < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"

    if respond_to? :public_folder
      set :public_folder, "#{dir}/server/public"
    else
      set :public, "#{dir}/server/public"
    end

    set :static, true

    helpers do
      include Resque::ServerHelper
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

    post "/failed/clear_retried" do
      Resque::Failure.clear_retried
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
