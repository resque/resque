require 'test_helper'
require 'resque/server'

context 'Resque::Server' do
  context 'show_args' do
    setup do
      @server = Resque::Server.new
    end
    
    test 'works with string arguments' do
      assert_equal "--- hello\n...\n", @server.helpers.show_args(['hello'])
    end
    
    test 'works with integer arguments' do
      assert_equal "--- 1\n...\n", @server.helpers.show_args([1])
    end
  end
end
