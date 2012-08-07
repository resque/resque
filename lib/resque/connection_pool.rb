module Resque
  class ConnectionPool
    attr_reader :size

    def initialize(url, size, timeout = nil)
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
        if conns.size < @size
          conn = Resque.create_connection(@url)
        else
          conn = conns.find {|k, v| !v }.first
        end
        conns[conn] = true
      end

      conn
    end
    
    def checkin(conn)
      @lock.synchronize do
        conns[conn] = false
      end
    end

    def with_connection
      conn = checkout
      yield(conn)
    ensure
      checkin(conn)
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
