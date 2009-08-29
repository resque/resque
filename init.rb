require 'resque'

if $redis
  Resque.redis = $redis
elsif defined? RAILS_ROOT
  require 'yaml'
  yaml = YAML.load_file File.join(RAILS_ROOT, 'config', 'resque.yml')
  Resque.redis = config[RAILS_ENV]

  if toad = config['hoptoad']
    Resque::Failure::Hoptoad.configure do |config|
      config.api_key = toad['api_key']
      config.secure = toad['secure']
      config.subdomain = toad['subdomain']
    end
  end
end
