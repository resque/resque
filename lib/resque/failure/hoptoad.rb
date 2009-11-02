require 'net/http'

module Resque
  module Failure
    # A Failure backend that sends exceptions raised by jobs to Hoptoad.
    #
    # To use it, put this code in an initializer, Rake task, or wherever:
    #
    #   Resque::Failure::Hoptoad.configure do |config|
    #     config.api_key = 'blah'
    #     config.secure = true
    #     config.subdomain = 'your_hoptoad_subdomain'
    #   end
    class Hoptoad < Base
      class << self
        attr_accessor :secure, :api_key, :subdomain
      end

      def self.url
        "http://#{subdomain}.hoptoadapp.com/" if subdomain
      end

      def self.count
        # We can't get the total # of errors from Hoptoad so we fake it
        # by asking Resque how many errors it has seen.
        Stat[:failed]
      end

      def self.configure
        yield self
        Resque::Failure.backend = self
      end

      def save
        data = {
          :api_key       => api_key,
          :error_class   => exception.class.name,
          :error_message => "#{exception.class.name}: #{exception.message}",
          :backtrace     => exception.backtrace,
          :environment   => {},
          :session       => {},
          :request       => {
            :params => payload.merge(:worker => worker.to_s, :queue => queue.to_s)
          }
        }

        send_to_hoptoad(:notice => data)
      end

      def send_to_hoptoad(data)
        http = use_ssl? ? :https : :http
        url = URI.parse("#{http}://hoptoadapp.com/notices/")

        http = Net::HTTP.new(url.host, url.port)
        headers = {
          'Content-type' => 'application/json',
          'Accept' => 'text/xml, application/xml'
        }

        http.read_timeout = 5 # seconds
        http.open_timeout = 2 # seconds
        http.use_ssl = use_ssl?

        begin
          response = http.post(url.path, Resque.encode(data), headers)
        rescue TimeoutError => e
          log "Timeout while contacting the Hoptoad server."
        end

        case response
        when Net::HTTPSuccess then
          log "Hoptoad Success: #{response.class}"
        else
          body = response.body if response.respond_to? :body
          log "Hoptoad Failure: #{response.class}\n#{body}"
        end
      end

      def use_ssl?
        self.class.secure
      end

      def api_key
        self.class.api_key
      end
    end
  end
end
