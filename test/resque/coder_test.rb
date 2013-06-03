require 'test_helper'

require 'resque/coder'

describe Resque::Coder do
  before do
    @coder = Resque::Coder.new
  end

  describe '#encode' do
    it 'should raise an exception' do
      assert_raises(Resque::EncodeException) {@coder.encode(nil)}
    end

    it 'aliased #dump should raise an exception' do
      assert_raises(Resque::EncodeException) {@coder.dump(nil)}
    end
  end

  describe '#decode' do
    it 'should raise an exception' do
      assert_raises(Resque::DecodeException) {@coder.decode(nil)}
    end

    it 'aliased #load should raise an exception' do
      assert_raises(Resque::DecodeException) {@coder.load(nil)}
    end
  end
end