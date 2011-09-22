begin
  require 'airbrake'
rescue LoadError
  raise "Can't find 'airbrake' gem. Please add it to your Gemfile or install it."
end

require 'resque/failure/thoughtbot'

module Resque
  module Failure
    class Airbrake < Base
      include Resque::Failure::Thoughtbot

      @klass = ::Airbrake
    end
  end
end
