require "test_helper"

module Resque
  describe ConnectionPool do
    it "takes a URL" do
      cp = ConnectionPool.new(REDIS_URL, 5)
      assert_equal 5, cp.size
    end

    it "limits connections" do
      cp = ConnectionPool.new(REDIS_URL, 5, 1)
      5.times { cp.checkout }

      assert_raises Timeout::Error do
        cp.checkout
      end
    end

    it "returns different connections each time you checkout" do
      cp = ConnectionPool.new(REDIS_URL, 5)
      refute_equal cp.checkout, cp.checkout
    end

    it "can checkout after you check back in" do
      cp   = ConnectionPool.new(REDIS_URL, 1)
      conn = cp.checkout
      cp.checkin(conn)
      assert_equal conn, cp.checkout
    end

    it "checkout unblocks on checkin" do
      cp = ConnectionPool.new(REDIS_URL, 1)
      conn = cp.checkout
      t = Thread.new { cp.checkout }
      cp.checkin(conn)

      assert_equal conn, t.join.value
    end

    it "yields a connection to a block" do
      cp = ConnectionPool.new(REDIS_URL, 1)
      c = nil
      cp.with_connection do |conn|
        c = conn
      end
      assert_equal c, cp.checkout
    end

    it 'checks in the connection if there is an exception' do
      cp = ConnectionPool.new(REDIS_URL, 1)
      c = nil
      assert_raises(RuntimeError) do
        cp.with_connection do |conn|
          c = conn
          raise
        end
      end
      assert_equal c, cp.checkout
    end

    it 'is fork aware' do
      skip if jruby?
      cp = ConnectionPool.new(REDIS_URL, 1)
      conn = cp.checkout

      Process.waitpid fork {
        assert cp.checkout
      }
    end

    it "only checkin a connection if checkout succeeded" do
      class MockRedis
        def initialize(server)
          @server = Resque.create_connection(server)
          @mocked = false
        end

        def method_missing(meth, *args, &block)
          # simulate failure
          unless @mocked
            @mocked = true
            raise "throw an error"
          end

          @server.send(meth, *args, &block)
        end
      end
      cp = ConnectionPool.new(MockRedis.new(REDIS_URL), 1)
      begin
        cp.with_connection {|conn| }
      rescue
      end

      assert cp.checkout, "Connection should not be nil"
    end
  end
end
