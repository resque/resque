require 'sinatra'
require 'resque'
require 'job'

module Demo
  class App
    get '/' do
      out = "<html>"
      out << "<h2>There are #{Resque.info[:pending]} pending and"
      out << "#{Resque.info[:processed]} processed jobs.</h2>"
      out << '<form method="POST"><input type="submit" value="Create New Job"/></form>'
    end

    post '/' do
      Resque.enqueue(Job, params)
      redirect "/"
    end
  end
end
