# Load the redis configuration from resque.yml
Resque.redis = YAML.load_file(File.join(Rails.root, "config", "resque.yml"))[Rails.env.to_s]
