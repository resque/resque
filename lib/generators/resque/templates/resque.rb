# Load the redis configuration from resque.yml
# this configuration can also be passed to resque-web
#
# RAILS_ENV=development resque-web rails_root/config/initializers/resque.rb

rails_root = Rails.root || File.dirname(__FILE__) + '/../..'
rails_env = Rails.env || 'development'

resque_config = YAML.load_file(rails_root.to_s + '/config/resque.yml')
Resque.redis = resque_config[rails_env]
