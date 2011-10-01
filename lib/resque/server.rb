require 'sinatra/base'
require 'mustache/sinatra'
require 'resque'
require 'resque/version'
require 'time'
require 'resque/server/helpers'
require 'resque/server/views/layout'
require 'resque/server/views/worker_list'
require 'resque/server/views/working_methods'
require 'resque/server/views/queue_methods'

if defined? Encoding
  Encoding.default_external = Encoding::UTF_8
end

module Resque
  class Server < Sinatra::Base
    register Mustache::Sinatra
    helpers Helpers
    
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"
    set :public, "#{dir}/server/public"
    set :static, true

    set :mustache, {
      :namespace => Resque,
      :templates => "#{dir}/server/templates",
      :views     => "#{dir}/server/views"
    }

    def show(page, layout = true)
      response["Cache-Control"] = "max-age=0, private, must-revalidate"
      begin
          mustache page.to_sym, {:layout => layout}, :resque => Resque
      rescue Errno::ECONNREFUSED
        mustache :error, :locals => {:error => "Can't connect to Redis! (#{Resque.redis_id})"}
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
      get "/#{page}.poll" do
        show_for_polling(page)
      end

      get "/#{page}/:id.poll" do
        show_for_polling(page)
      end
    end

    %w( overview queues working workers key ).each do |page|
      get "/#{page}" do
        show page
      end

      get "/#{page}/:id" do
        show page
      end
    end

    post "/queues/:id/remove" do
      Resque.remove_queue(params[:id])
      redirect u('queues')
    end

    get "/failed" do
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

    post "/failed/requeue/all" do
      Resque::Failure.count.times do |num|
        Resque::Failure.requeue(num)
      end
      redirect u('failed')
    end

    get "/failed/requeue/:index" do
      Resque::Failure.requeue(params[:index])
      if request.xhr?
        return Resque::Failure.all(params[:index])['retried_at']
      else
        redirect u('failed')
      end
    end

    get "/failed/remove/:index" do
      Resque::Failure.remove(params[:index])
      redirect u('failed')
    end

    get "/stats" do
      redirect url_path("/stats/resque")
    end

    get "/stats/:id" do
      show :stats
    end

    get "/stats/keys/:key" do
      show :stats
    end

    get "/stats.txt" do
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
  end
end
