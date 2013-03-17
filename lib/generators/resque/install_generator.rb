require "rails"

module Resque::Generators
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path('../templates', __FILE__)

    def copy_files
      copy_file "resque.rb", "config/initializers/resque.rb"
      copy_file "resque.yml", "config/resque.yml"
    end
  end
end
