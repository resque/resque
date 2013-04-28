require 'test_helper'

describe String do
  it "#constantize" do
    assert_same Kernel, "Kernel".constantize
    assert_same MiniTest::Unit::TestCase, 'MiniTest::Unit::TestCase'.constantize
    assert_raises NameError do
      'Object::MissingConstant'.constantize
    end
  end
end