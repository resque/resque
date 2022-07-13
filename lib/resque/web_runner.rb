require 'open-uri'
require 'logger'
require 'optparse'
require 'fileutils'
require 'rack'
require 'resque/server'

# only used with `bin/resque-web`
# https://github.com/resque/resque/pull/1780

module Resque
  WINDOWS = !!(RUBY_PLATFORM =~ /(mingw|bccwin|wince|mswin32)/i)
  JRUBY = !!(RbConfig::CONFIG["RUBY_INSTALL_NAME"] =~ /^jruby/i)

  class WebRunner
    attr_reader :app, :app_name, :filesystem_friendly_app_name,
      :rack_handler, :port, :options, :args

    PORT       = 5678
    HOST       = WINDOWS ? 'localhost' : '0.0.0.0'

    def initialize(*runtime_args)
      @options = runtime_args.last.is_a?(Hash) ? runtime_args.pop : {}

      self.class.logger.level = options[:debug] ? Logger::DEBUG : Logger::INFO

      @app      = Resque::Server
      @app_name = 'resque-web'
      @filesystem_friendly_app_name = @app_name.gsub(/\W+/, "_")

      @args = load_options(runtime_args)

      @rack_handler = (s = options[:rack_handler]) ? Rack::Handler.get(s) : setup_rack_handler

      case option_parser.command
      when :help
        puts option_parser
      when :kill
        kill!
      when :status
        status
      when :version
        puts "resque #{Resque::VERSION}"
        puts "rack #{Rack::VERSION.join('.')}"
        puts "sinatra #{Sinatra::VERSION}" if defined?(Sinatra)
      else
        before_run
        start unless options[:start] == false
      end
    end

    def launch_path
      if options[:launch_path].respond_to?(:call)
        options[:launch_path].call(self)
      else
        options[:launch_path]
      end
    end

    def app_dir
      if !options[:app_dir] && !ENV['HOME']
        raise ArgumentError.new("nor --app-dir neither ENV['HOME'] defined")
      end
      options[:app_dir] || File.join(ENV['HOME'], filesystem_friendly_app_name)
    end

    def pid_file
      options[:pid_file] || File.join(app_dir, "#{filesystem_friendly_app_name}.pid")
    end

    def url_file
      options[:url_file] || File.join(app_dir, "#{filesystem_friendly_app_name}.url")
    end

    def log_file
      options[:log_file] || File.join(app_dir, "#{filesystem_friendly_app_name}.log")
    end

    def host
      options.fetch(:host) { HOST }
    end

    def url
      "http://#{host}:#{port}"
    end

    def before_run
      if (namespace = options[:redis_namespace])
        logger.info "Using Redis namespace '#{namespace}'"
        Resque.redis.namespace = namespace
      end
      if (redis_conf = options[:redis_conf])
        logger.info "Using Redis connection '#{redis_conf}'"
        Resque.redis = redis_conf
      end
      if (url_prefix = options[:url_prefix])
        logger.info "Using URL Prefix '#{url_prefix}'"
        Resque::Server.url_prefix = url_prefix
      end
      app.set(options.merge web_runner: self)
      path = (ENV['RESQUECONFIG'] || args.first)
      load_config_file(path.to_s.strip) if path
    end

    def start(path = launch_path)
      logger.info "Running with Windows Settings" if WINDOWS
      logger.info "Running with JRuby" if JRUBY
      logger.info "Starting '#{app_name}'..."

      check_for_running(path)
      find_port
      write_url
      launch!(url, path)
      daemonize! unless options[:foreground]
      run!
    rescue RuntimeError => e
      logger.warn "There was an error starting '#{app_name}': #{e}"
      exit
    end

    def find_port
      if @port = options[:port]
        announce_port_attempted

        unless port_open?
          logger.warn "Port #{port} is already in use. Please try another. " +
                      "You can also omit the port flag, and we'll find one for you."
        end
      else
        @port = PORT
        announce_port_attempted

        until port_open?
          @port += 1
          announce_port_attempted
        end
      end
    end

    def announce_port_attempted
      logger.info "trying port #{port}..."
    end

    def port_open?(check_url = nil)
      begin
        check_url ||= url
        options[:no_proxy] ? uri_open(check_url, :proxy => nil) : uri_open(check_url)
        false
      rescue Errno::ECONNREFUSED, Errno::EPERM, Errno::ETIMEDOUT
        true
      end
    end

    def uri_open(*args)
      (RbConfig::CONFIG['ruby_version'] < '2.7') ? open(*args) : URI.open(*args)
    end

    def write_url
      # Make sure app dir is setup
      FileUtils.mkdir_p(app_dir)
      File.open(url_file, 'w') {|f| f << url }
    end

    def check_for_running(path = nil)
      if File.exist?(pid_file) && File.exist?(url_file)
        running_url = File.read(url_file)
        if !port_open?(running_url)
          logger.warn "'#{app_name}' is already running at #{running_url}"
          launch!(running_url, path)
          exit!(1)
        end
      end
    end

    def run!
      logger.info "Running with Rack handler: #{@rack_handler.inspect}"

      rack_handler.run app, :Host => host, :Port => port do |server|
        kill_commands.each do |command|
          trap(command) do
            ## Use thins' hard #stop! if available, otherwise just #stop
            server.respond_to?(:stop!) ? server.stop! : server.stop
            logger.info "'#{app_name}' received INT ... stopping"
            delete_pid!
          end
        end
      end
    end

    # Adapted from Rackup
    def daemonize!
      if JRUBY
        # It's not a true daemon but when executed with & works like one
        thread = Thread.new {daemon_execute}
        thread.join

      elsif RUBY_VERSION < "1.9"
        logger.debug "Parent Process: #{Process.pid}"
        exit!(0) if fork
        logger.debug "Child Process: #{Process.pid}"
        daemon_execute

      else
        Process.daemon(true, true)
        daemon_execute
      end
    end

    def daemon_execute
      File.umask 0000
      FileUtils.touch log_file
      STDIN.reopen    log_file
      STDOUT.reopen   log_file, "a"
      STDERR.reopen   log_file, "a"

      logger.debug "Child Process: #{Process.pid}"

      File.open(pid_file, 'w') {|f| f.write("#{Process.pid}") }
      at_exit { delete_pid! }
    end

    def launch!(specific_url = nil, path = nil)
      return if options[:skip_launch]
      cmd = WINDOWS ? "start" : "open"
      system "#{cmd} #{specific_url || url}#{path}"
    end

    def kill!
      pid = File.read(pid_file)
      logger.warn "Sending #{kill_command} to #{pid.to_i}"
      Process.kill(kill_command, pid.to_i)
    rescue => e
      logger.warn "pid not found at #{pid_file} : #{e}"
    end

    def status
      if File.exists?(pid_file)
        logger.info "'#{app_name}' running"
        logger.info "PID #{File.read(pid_file)}"
        logger.info "URL #{File.read(url_file)}" if File.exists?(url_file)
      else
        logger.info "'#{app_name}' not running!"
      end
    end

    # Loads a config file at config_path and evals it in the context of the @app.
    def load_config_file(config_path)
      abort "Can not find config file at #{config_path}" if !File.readable?(config_path)
      config = File.read(config_path)
      # trim off anything after __END__
      config.sub!(/^__END__\n.*/, '')
      @app.module_eval(config)
    end

    def self.logger=(logger)
      @logger = logger
    end

    def self.logger
      @logger ||= LOGGER if defined?(LOGGER)
      if !@logger
        @logger           = Logger.new(STDOUT)
        @logger.formatter = Proc.new {|s, t, n, msg| "[#{t}] #{msg}\n"}
        @logger
      end
      @logger
    end

    def logger
      self.class.logger
    end

  private
    def setup_rack_handler
      # First try to set Rack handler via a special hook we honor
      @rack_handler = if @app.respond_to?(:detect_rack_handler)
        @app.detect_rack_handler

      # If they aren't using our hook, try to use their @app.server settings
      elsif @app.respond_to?(:server) and @app.server
        # If :server isn't set, it returns an array of possibilities,
        # sorted from most to least preferable.
        if @app.server.is_a?(Array)
          handler = nil
          @app.server.each do |server|
            begin
              handler = Rack::Handler.get(server)
              break
            rescue LoadError, NameError => e
              next
            end
          end
          handler

        # :server might be set explicitly to a single option like "mongrel"
        else
          Rack::Handler.get(@app.server)
        end

      # If all else fails, we'll use Thin
      else
        JRUBY ? Rack::Handler::WEBrick : Rack::Handler::Thin
      end
    end

    def load_options(runtime_args)
      @args = option_parser.parse!(runtime_args)
      options.merge!(option_parser.options)
      args
    rescue OptionParser::MissingArgument => e
      logger.warn "#{e}, run -h for options"
      exit
    end

    def option_parser
      @option_parser ||= Parser.new(app_name)
    end

    class Parser < OptionParser
      attr_reader :command, :options

      def initialize(app_name)
        super("", 24, '  ')
        self.banner = "Usage: #{app_name} [options]"

        @options = {}
        basename = app_name.gsub(/\W+/, "_")
        on('-K', "--kill", "kill the running process and exit") { @command = :kill }
        on('-S', "--status", "display the current running PID and URL then quit") { @command = :status }
        string_option("-s", "--server SERVER", "serve using SERVER (thin/mongrel/webrick)", :rack_handler)
        string_option("-o", "--host HOST", "listen on HOST (default: #{HOST})", :host)
        string_option("-p", "--port PORT", "use PORT (default: #{PORT})", :port)
        on("-x", "--no-proxy", "ignore env proxy settings (e.g. http_proxy)") { opts[:no_proxy] = true }
        boolean_option("-F", "--foreground", "don't daemonize, run in the foreground", :foreground)
        boolean_option("-L", "--no-launch", "don't launch the browser", :skip_launch)
        boolean_option('-d', "--debug", "raise the log level to :debug (default: :info)", :debug)
        string_option("--app-dir APP_DIR", "set the app dir where files are stored (default: ~/#{basename}/)", :app_dir)
        string_option("-P", "--pid-file PID_FILE", "set the path to the pid file (default: app_dir/#{basename}.pid)", :pid_file)
        string_option("--log-file LOG_FILE", "set the path to the log file (default: app_dir/#{basename}.log)", :log_file)
        string_option("--url-file URL_FILE", "set the path to the URL file (default: app_dir/#{basename}.url)", :url_file)
        string_option('-N NAMESPACE', "--namespace NAMESPACE", "set the Redis namespace", :redis_namespace)
        string_option('-r redis-connection', "--redis redis-connection", "set the Redis connection string", :redis_conf)
        string_option('-a url-prefix', "--append url-prefix", "set reverse_proxy friendly prefix to links", :url_prefix)
        separator ""
        separator "Common options:"
        on_tail("-h", "--help", "Show this message") { @command = :help }
        on_tail("--version", "Show version") { @command = :version }
      end

      def boolean_option(*argv)
        k = argv.pop; on(*argv) { options[k] = true }
      end

      def string_option(*argv)
        k = argv.pop; on(*argv) { |value| options[k] = value }
      end
    end

    def kill_commands
      WINDOWS ? [1] : [:INT, :TERM]
    end

    def kill_command
      kill_commands[0]
    end

    def delete_pid!
      File.delete(pid_file) if File.exist?(pid_file)
    end
  end

end
