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
  end
end
