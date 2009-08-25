require 'resque'

if defined? RAILS_ROOT
  require 'yaml'
  config = YAML.load_file File.join(RAILS_ROOT, 'config', 'resque.yml')
  Resque.redis = config[RAILS_ENV]
end
