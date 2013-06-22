# encoding: utf-8
require 'test_helper'

describe Hash do
  it '#symbolize_keys' do
    source = {'foo' => 'bar', 'baz' => 'bingo'}
    result = source.symbolize_keys
    assert_equal({foo: 'bar', baz: 'bingo'}, result, 'result must have sym keys')
    assert_equal({'foo'=>'bar', 'baz'=>'bingo'}, source, 'source unchanged')
  end

  it '#symbolize_keys!' do
    source = {'foo' => 'bar', 'baz' => 'bingo'}
    result = source.symbolize_keys!
    assert_same source, result
    assert_equal({foo: 'bar', baz: 'bingo'}, result, 'result must have sym keys')

  end

  it '#slice' do
    source = {foo: 'bar', baz: 'bingo', pop: 'fizz' }
    result = source.slice(:foo, :pop)
    assert_equal({foo: 'bar', pop: 'fizz'}, result)
  end
end
