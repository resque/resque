require 'test_helper'

describe "Resque::Stat" do
  before do
    @original_data_store = Resque::Stat.data_store
    @dummy_data_store = Object.new
    Resque::Stat.data_store = @dummy_data_store
  end

  after do
    Resque::Stat.data_store = @original_data_store
  end

  it '#redis show deprecation warning' do
    assert_output(nil, /\[Resque\] \[Deprecation\]/ ) { Resque::Stat.redis }
  end

  it '#redis returns data_store' do
    data_store = Resque::Stat.redis
    assert_equal @dummy_data_store, data_store
  end

  it "#get" do
    @dummy_data_store.expects(:stat).with('hello')
    Resque::Stat.get('hello')
  end

  it "#[]" do
    @dummy_data_store.expects(:stat).with('hello')
    Resque::Stat['hello']
  end

  it "#incr" do
    @dummy_data_store.expects(:increment_stat).with('hello', 2)
    Resque::Stat.incr('hello', 2)
  end

  it "#<<" do
    @dummy_data_store.expects(:increment_stat).with('hello', 1)
    Resque::Stat << 'hello'
  end

  it "#decr" do
    @dummy_data_store.expects(:decrement_stat).with('hello', 2)
    Resque::Stat.decr('hello', 2)
  end

  it "#>>" do
    @dummy_data_store.expects(:decrement_stat).with('hello', 1)
    Resque::Stat >> 'hello'
  end

  it '#clear' do
    @dummy_data_store.expects(:clear_stat).with('hello')
    Resque::Stat.clear('hello')
  end
end
