require 'bundler'

Bundler.require

require 'capybara'
require 'capybara/dsl'
require 'rack/test'

require 'test_site'
Capybara.app = Resque::TestSite
 
require 'minitest/autorun'

class MiniTest::Spec
  include Capybara::DSL
  include Rack::Test::Methods
end

describe "one full round trip" do

  describe Resque::TestSite do
    it "shows a site" do
      visit '/'

      assert_equal 'Hello world!', page.body
    end
  end
end
