require 'resque'

# railsy
root = ENV['RAILS_ROOT'] || (defined?(RAILS_ROOT) && RAILS_ROOT)
env  = ENV['RAILS_ENV']  || (defined?(RAILS_ENV) && RAILS_ENV)

# non-rails
root ||= File.expand_path(ENV['CONFIG']) if ENV['CONFIG']
env  ||= ENV['ENV']

if !env
  puts "** No ENV or RAILS_ENV found; assuming `development`"
  env = 'development'
end

if root
  yml  = 'resque.yml'
  file = [ File.join(root, 'config', yml), File.join(root, yml) ].detect do |f|
    File.exists? f
  end

  if file
    require 'yaml'
    config = YAML.file_load(file)
  else
    raise "Can't find resque.yml in #{root}"
  end

  Resque.redis = config[env]

  if toad = config['hoptoad']
    require 'resque/failure/hoptoad'
    Resque::Failure::Hoptoad.configure do |config|
      config.api_key   = toad['api_key']
      config.secure    = toad['secure']
      config.subdomain = toad['subdomain']
    end
  end
end
