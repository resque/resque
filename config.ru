#!/usr/bin/env ruby
require 'logger'

APP_ROOT = File.expand_path File.dirname(__FILE__) + '/lib'
$LOAD_PATH.unshift APP_ROOT
require 'resque/server'

use Rack::ShowExceptions
run Resque::Server.new
