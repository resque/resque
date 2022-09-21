require 'test_helper'
require 'rack/test'
require 'resque/server'
require 'resque/web_runner'

describe 'Resque::WebRunner' do
  def web_runner(*args)
    Resque::WebRunner.any_instance.stubs(:daemonize!).once

    Resque::JRUBY ? Rack::Handler::WEBrick.stubs(:run).once : Rack::Handler::Thin.stubs(:run).once

    @runner = Resque::WebRunner.new(*args)
  end

  before do
    ENV['RESQUECONFIG'] = 'examples/resque_config.rb'

    FileUtils.rm_rf(File.join(File.dirname(__FILE__), 'tmp'))
    @log = StringIO.new
    Resque::WebRunner.logger = Logger.new(@log)
  end

  describe 'creating an instance' do

    describe 'basic usage' do
      before do
        Resque::WebRunner.any_instance.expects(:system).once
        web_runner("route","--debug", sessions: true)
      end

      it "sets app" do
        assert_equal @runner.app, Resque::Server
      end

      it "sets app name" do
        assert_equal @runner.app_name, 'resque-web'
        assert_equal @runner.filesystem_friendly_app_name, 'resque_web'
      end

      it "stores options" do
        assert @runner.options[:sessions]
      end

      it "puts unparsed args into args" do
        assert_equal @runner.args, ["route"]
      end

      it "parses options into @options" do
        assert @runner.options[:debug]
      end

      it "writes the app dir" do
        assert File.exist?(@runner.app_dir)
      end

      it "writes a url with the port" do
        assert File.exist?(@runner.url_file)
        assert File.read(@runner.url_file).match(/0.0.0.0\:#{@runner.port}/)
      end

      it "knows where to find the pid file" do
        assert_equal @runner.pid_file, \
          File.join(@runner.app_dir, @runner.filesystem_friendly_app_name + ".pid")
        # assert File.exist?(@runner.pid_file), "#{@runner.pid_file} not found."
      end
    end

    describe 'with a sinatra app using an explicit server setting' do
      def web_runner(*args)
        Resque::WebRunner.any_instance.stubs(:daemonize!).once
        Rack::Handler::WEBrick.stubs(:run).once
        @runner = Resque::WebRunner.new(*args)
      end

      before do
        Resque::Server.set :server, "webrick"
        Rack::Handler::WEBrick.stubs(:run)
        web_runner("route","--debug", skip_launch: true, sessions: true)
      end
      after do
        Resque::Server.set :server, false
      end

      it 'sets the rack handler automatically' do
        assert_equal @runner.rack_handler, Rack::Handler::WEBrick
      end
    end

    describe 'with a sinatra app without an explicit server setting' do
      def web_runner(*args)
        Resque::WebRunner.any_instance.stubs(:daemonize!).once
        Rack::Handler::WEBrick.stubs(:run).once
        @runner = Resque::WebRunner.new(*args)
      end

      before do
        Resque::Server.set :server, ["invalid", "webrick", "thin"]
        Rack::Handler::WEBrick.stubs(:run)
        web_runner("route", "--debug", skip_launch: true, sessions: true)
      end

      after do
        Resque::Server.set :server, false
      end

      it 'sets the first valid rack handler' do
        assert_equal @runner.rack_handler, Rack::Handler::WEBrick
      end
    end

    describe 'with a sinatra app without available server settings' do
      before do
        Resque::Server.set :server, ["invalid"]
      end

      after do
        Resque::Server.set :server, false
      end

      it 'raises an error indicating that no available Rack handler was found' do
        err = assert_raises StandardError do
          Resque::WebRunner.new(skip_launch: true, sessions: true)
        end
        assert_match('No available Rack handler (e.g. WEBrick, Thin, Puma, etc.) was found.', err.message)
      end
    end

    describe 'with a simple rack app' do
      before do
        web_runner(skip_launch: true, sessions: true)
      end

      it "sets default rack handler to thin when in ruby and WEBrick when in jruby" do
        if Resque::JRUBY
          assert_equal @runner.rack_handler, Rack::Handler::WEBrick
        else
          assert_equal @runner.rack_handler, Rack::Handler::Thin
        end
      end
    end

    describe 'with a launch path specified as a proc' do
      it 'evaluates the proc in the context of the runner' do
        Resque::WebRunner.any_instance.expects(:system).once.with {|s| s =~ /\?search\=blah$/ }
        web_runner("--debug", "blah", launch_path: Proc.new {|r| "?search=#{r.args.first}" })
        assert @runner.options[:launch_path].is_a?(Proc)
      end
    end

    describe 'with a launch path specified as string' do
      it 'launches to the specific path' do
        Resque::WebRunner.any_instance.expects(:system).once.with {|s| s =~ /\?search\=blah$/ }
        web_runner("--debug", "blah", launch_path: "?search=blah")
        assert_equal @runner.options[:launch_path], "?search=blah"
      end
    end

    describe 'without environment' do

      before do
        @home = ENV.delete('HOME')
        @app_dir = './test/tmp'
      end

      after { ENV['HOME'] = @home }

      it 'should be ok with --app-dir' do
        web_runner(skip_launch: true, app_dir: @app_dir)
        assert_equal @runner.app_dir, @app_dir
      end

      it 'should raise an exception without --app-dir' do
        success = false
        begin
          Resque::WebRunner.new(skip_launch: true)
        rescue ArgumentError
          success = true
        end
        assert success, "ArgumentError not raised."
      end

    end

  end

end
