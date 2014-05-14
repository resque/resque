require 'test_helper'

describe Resque::Coder do
  before do
    @coder = Resque::Coder.new
  end

  describe '#encode' do
    it 'raises an exception' do
      assert_raises(Resque::EncodeException) {@coder.encode(nil)}
    end

    it 'aliased #dump should raise an exception' do
      assert_raises(Resque::EncodeException) {@coder.dump(nil)}
    end
  end

  describe '#decode' do
    it 'raises an exception' do
      assert_raises(Resque::DecodeException) {@coder.decode(nil)}
    end

    it 'aliased #load raises an exception' do
      assert_raises(Resque::DecodeException) {@coder.load(nil)}
    end
  end
end
