require 'resque'

if defined? RAILS_ROOT
  config = YAML.load_file File.join(RAILS_ROOT, 'config', 'resque.yml')
  ::QUEUE = Resque.new(config[RAILS_ENV])
end
