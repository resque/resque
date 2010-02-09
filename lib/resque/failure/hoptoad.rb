require 'net/http'
require 'builder'

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
      #from the hoptoad plugin
      INPUT_FORMAT = %r{^([^:]+):(\d+)(?::in `([^']+)')?$}.freeze
      
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
        http = use_ssl? ? :https : :http
        url = URI.parse("#{http}://hoptoadapp.com/notifier_api/v2/notices")

        http = Net::HTTP.new(url.host, url.port)
        headers = {
          'Content-type' => 'text/xml',
          'Accept' => 'text/xml, application/xml'
        }

        http.read_timeout = 5 # seconds
        http.open_timeout = 2 # seconds
        
        http.use_ssl = use_ssl?

        begin
          response = http.post(url.path, xml, headers)
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
      
      def xml
        x = Builder::XmlMarkup.new
        x.instruct!
        x.notice :version=>"2.0" do
          x.tag! "api-key", api_key
          x.notifier do
            x.name "Resqueue"
            x.version "0.1"
            x.url "http://github.com/defunkt/resque"
          end
          x.error do
            x.class exception.class.name
            x.message "#{exception.class.name}: #{exception.message}"
            x.backtrace do
              fill_in_backtrace_lines(x)
            end
          end
          x.request do
            x.url queue.to_s
            x.component worker.to_s
            x.params do
              x.var :key=>"payload_class" do
                x.text! payload["class"].to_s
              end
              x.var :key=>"payload_args" do
                x.text! payload["args"].to_s
              end
            end
          end
          x.tag!("server-environment") do
            x.tag!("environment-name",RAILS_ENV)
          end
          
        end
      end
      
      def fill_in_backtrace_lines(x)
        exception.backtrace.each do |unparsed_line|
          _, file, number, method = unparsed_line.match(INPUT_FORMAT).to_a
          x.line :file=>file,:number=>number
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
