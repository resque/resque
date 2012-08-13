module Resque
  class ConnectionPool
    attr_reader :size

    def initialize(url = Resque.redis, size = 5, timeout = nil)
      @lock    = Monitor.new
      @cv      = @lock.new_cond
      @url     = url
      @size    = size
      @timeout = timeout
      @conns   = Hash.new { |h,k|
        h[Process.pid] = {}
      }
    end

    def checkout
      conn = nil

      @lock.synchronize do
        Timeout.timeout(@timeout) do
          @cv.wait_while { checked_out_conns.length >= @size }
        end
        available_conn = conns.find {|k, v| !v }
        if conns.size < @size && available_conn.nil?
          conn = Resque.create_connection(@url)
        else
          conn = available_conn.first
        end
        conns[conn] = true
      end

      conn
    end
    
    def checkin(conn)
      @lock.synchronize do
        conns[conn] = false
        @cv.broadcast
      end
    end

    def with_connection
      conn = checkout
      yield(conn)
    ensure
      checkin(conn) if conn
    end

    private
    def checked_out_conns
      conns.find_all {|k, v| v }.map(&:first)
    end

    def conns
      @conns[Process.pid]
    end
  end
end
