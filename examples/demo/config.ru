#!/usr/bin/env ruby
require 'logger'
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'
require 'app'

use Rack::ShowExceptions
run Demo::App.new
