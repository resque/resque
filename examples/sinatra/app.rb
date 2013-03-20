require "rubygems"
require 'sinatra'
require 'resque'
require 'redis'
require './job'

#Setup redis for resque
Resque.redis = Redis.new

get '/' do
  @info = Resque.info
  erb :index
end

post '/' do
  Resque.enqueue(Job, params)
  redirect "/"
end

post '/failing' do
  Resque.enqueue(FailingJob, params)
  redirect "/"
end

__END__

@@ index
<html>
  <head><title>Resque Demo</title></head>
  <body>
    <p>
      There are <%= @info[:pending] %> pending and <%= @info[:processed] %> processed jobs across <%= @info[:queues] %> queues.
    </p>
    <form method="POST">
      <input type="submit" value="Create New Job"/>
    </form>

    <form action='/failing' method='POST'>
      <input type="submit" value="Create Failing New Job"/>
    </form>
  </body>
</html>
