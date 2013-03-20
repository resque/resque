require 'sinatra/base'

module Resque
  class TestSite < Sinatra::Base
    get '/' do
      'Hello world!'
    end
  end
end
