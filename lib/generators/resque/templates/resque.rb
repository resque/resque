# Load the redis configuration from resque.yml

Resque.redis = YAML.load_file(Rails.root.join("/config/resque.yml"))[Rails.env.to_s]
