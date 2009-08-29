#!/usr/bin/env ruby
require 'logger'

require 'init' if File.exists? 'init.rb'

$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/lib')
require 'resque/server'

use Rack::ShowExceptions
run Resque::Server.new
