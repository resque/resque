require 'test_helper'
require 'resque/json_coder'

describe Resque::JsonCoder do

  let(:coder) { Resque::JsonCoder.new }

  describe "#encode" do
    it "encodes a string as JSON" do
      assert_equal "{\"foo\":1}", coder.encode({"foo" => 1})
    end

    it "raises with invalid input" do
      lambda { coder.encode("\xC2") }.must_raise(Resque::EncodeException)
    end
  end

  describe "#decode" do
    it "decodes valid JSON" do
      result = {"test" => 1}
      assert_equal result, coder.decode('{"test": 1}')
    end

    it "raises with malformed JSON" do
      lambda { coder.decode('{test: 1}') }.must_raise(Resque::DecodeException)
    end
  end
end
