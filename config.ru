#!/usr/bin/env ruby
require 'logger'

APP_ROOT = File.expand_path File.dirname(__FILE__) + '/lib'
$LOAD_PATH.unshift APP_ROOT
require 'resque/server'

use Rack::ShowExceptions
app = Resque::Server.new

begin
  require 'thin'
  Rack::Handler::Thin.run(app, :Port => 4000 )
rescue LoadError
  run app
end
