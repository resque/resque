require "test_helper"

module Resque
  describe ConnectionPool do
    it "with_conneciton does not deadlock on checkout exceptions" do
      cp = Class.new(ConnectionPool) {
        def checkout
          raise "omg"
        end
      }.new(REDIS_URL, 5)
      e = assert_raises(RuntimeError) do
        cp.with_connection { }
      end
      assert_equal 'omg', e.message
    end

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

    it "avoids deadlocks" do
      cp = ConnectionPool.new(REDIS_URL, 2)
      cp.with_connection {|conn| conn.rpush(:foo, "hello") }

      threads = []
      5.times do
        threads << Thread.new do
          cp.with_connection do |conn|
            conn.blpop(:foo, 1)
          end
        end
      end

      begin
        threads.each {|t| t.join }
      rescue Exception => e
        refute_equal "fatal", e.class.to_s, e.message
      end
    end

    it "reuse existing connections first if available" do
      cp   = ConnectionPool.new(REDIS_URL, 2)
      conn = nil
      cp.with_connection {|c| conn = c }

      assert_equal conn, cp.checkout, "Does not use the same connection"
    end
  end
end
