#!/usr/bin/env ruby
require 'logger'

use Rack::ShowExceptions
run Demo::App.new
