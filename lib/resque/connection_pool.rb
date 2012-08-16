module Resque
  class ConnectionPool
    attr_reader :size

    DUMMY = Object.new

    def initialize(url = Resque.redis, size = 5, timeout = nil)
      @url     = url
      @size    = size
      @timeout = timeout
      @conns   = Hash.new { |h,k|
        stack          = SizedStack.new(size)
        size.times { stack << DUMMY }
        h[Process.pid] = stack
      }
    end

    def checkout
      conn = Timeout.timeout(@timeout) { conns.pop }
      conn = Resque.create_connection(@url) if conn == DUMMY

      conn
    end

    def checkin(conn)
      conns << conn
    end

    def with_connection
      conn = checkout
      yield(conn)
    ensure
      checkin(conn) if conn
    end

    private
    def conns
      @conns[Process.pid]
    end
  end
end
