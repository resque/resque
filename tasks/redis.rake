# Inspired by rabbitmq.rake the Redbox project at http://github.com/rick/redbox/tree/master
require 'fileutils'
require 'open-uri'
require 'pathname'

class RedisRunner
  def self.redis_dir
    @redis_dir ||= if ENV['PREFIX']
                     Pathname.new(ENV['PREFIX'])
                   else
                     Pathname.new(`which redis-server`) + '..' + '..'
                   end
  end

  def self.bin_dir
    redis_dir + 'bin'
  end

  def self.config
    @config ||= if File.exists?(redis_dir + 'etc/redis.conf')
                  redis_dir + 'etc/redis.conf'
                else
                  redis_dir + '../etc/redis.conf'
                end
  end

  def self.dtach_socket
    '/tmp/redis.dtach'
  end

  # Just check for existance of dtach socket
  def self.running?
    File.exists? dtach_socket
  end

  def self.start
    puts 'Detach with Ctrl+\  Re-attach with rake redis:attach'
    sleep 1
    command = "#{bin_dir}/dtach -A #{dtach_socket} #{bin_dir}/redis-server #{config}"
    sh command
  end

  def self.attach
    exec "#{bin_dir}/dtach -a #{dtach_socket}"
  end

  def self.stop
    sh 'echo "SHUTDOWN" | nc localhost 6379'
  end
end

INSTALL_DIR = ENV['INSTALL_DIR'] || '/tmp/redis'

namespace :redis do
  desc 'About redis'
  task :about do
    puts "\nSee http://code.google.com/p/redis/ for information about redis.\n\n"
  end

  desc 'Start redis'
  task :start do
    RedisRunner.start
  end

  desc 'Stop redis'
  task :stop do
    RedisRunner.stop
  end

  desc 'Restart redis'
  task :restart do
    RedisRunner.stop
    RedisRunner.start
  end

  desc 'Attach to redis dtach socket'
  task :attach do
    RedisRunner.attach
  end

  desc <<-DOC
  Install the latest verison of Redis from Github (requires git, duh).
    Use INSTALL_DIR env var like "rake redis:install INSTALL_DIR=~/tmp"
    in order to get an alternate location for your install files.
  DOC

  task :install => [:about, :download, :make] do
    bin_dir = '/usr/bin'
    conf_dir = '/etc'

    if ENV['PREFIX']
      bin_dir = "#{ENV['PREFIX']}/bin"
      sh "mkdir -p #{bin_dir}" unless File.exists?("#{bin_dir}")

      conf_dir = "#{ENV['PREFIX']}/etc"
      sh "mkdir -p #{conf_dir}" unless File.exists?("#{conf_dir}")
    end

    %w(redis-benchmark redis-cli redis-server).each do |bin|
      sh "cp #{INSTALL_DIR}/src/#{bin} #{bin_dir}"
    end

    puts "Installed redis-benchmark, redis-cli and redis-server to #{bin_dir}"

    unless File.exists?("#{conf_dir}/redis.conf")
      sh "cp #{INSTALL_DIR}/redis.conf #{conf_dir}/redis.conf"
      puts "Installed redis.conf to #{conf_dir} \n You should look at this file!"
    end
  end

  task :make do
    sh "cd #{INSTALL_DIR}/src && make clean"
    sh "cd #{INSTALL_DIR}/src && make"
  end

  desc "Download package"
  task :download do
    sh "rm -rf #{INSTALL_DIR}/" if File.exists?("#{INSTALL_DIR}/.svn")
    sh "git clone git://github.com/antirez/redis.git #{INSTALL_DIR}" unless File.exists?(INSTALL_DIR)
    sh "cd #{INSTALL_DIR} && git pull" if File.exists?("#{INSTALL_DIR}/.git")
  end
end

namespace :dtach do
  desc 'About dtach'
  task :about do
    puts "\nSee http://dtach.sourceforge.net/ for information about dtach.\n\n"
  end

  desc 'Install dtach 0.8 from source'
  task :install => [:about, :download, :make] do

    bin_dir = "/usr/bin"


    if ENV['PREFIX']
      bin_dir = "#{ENV['PREFIX']}/bin"
      sh "mkdir -p #{bin_dir}" unless File.exists?("#{bin_dir}")
    end

    sh "cp #{INSTALL_DIR}/dtach-0.8/dtach #{bin_dir}"
  end

  task :make do
    sh "cd #{INSTALL_DIR}/dtach-0.8/ && ./configure && make"
  end

  desc "Download package"
  task :download do
    unless File.exists?("#{INSTALL_DIR}/dtach-0.8.tar.gz")
      require 'net/http'

      url = 'http://downloads.sourceforge.net/project/dtach/dtach/0.8/dtach-0.8.tar.gz'
      open("#{INSTALL_DIR}/dtach-0.8.tar.gz", 'wb') do |file| file.write(open(url).read) end
    end

    unless File.directory?("#{INSTALL_DIR}/dtach-0.8")
      sh "cd #{INSTALL_DIR} && tar xzf dtach-0.8.tar.gz"
    end
  end
end
