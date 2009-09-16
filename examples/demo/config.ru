#!/usr/bin/env ruby
require 'logger'
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'
require 'app'
require 'resque/server'

use Rack::ShowExceptions

map = Rack::URLMap.new({
  "/"       => Demo::App.new,
  "/resque" => Resque::Server.new
})

run map
