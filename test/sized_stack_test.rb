require "test_helper"

module Resque
  describe SizedStack do
    it "can be constructed" do
      assert Resque::SizedStack.new(10)
    end

    it "pops off what we push" do
      stack = Resque::SizedStack.new 10
      thing = Object.new
      stack.push thing
      assert_equal thing, stack.pop
    end

    it "is a stack" do
      stack = Resque::SizedStack.new 10
      items = 10.times.map { Object.new }
      items.each { |i| stack << i }
      items.reverse_each do |i|
        assert_equal i, stack.pop
      end
    end
  end
end
