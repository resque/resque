require 'mono_logger'
require 'redis/namespace'

require 'resque/version'
require 'resque/config'

require 'resque/errors'

require 'resque/failure/base'
require 'resque/failure'
require 'resque/failure/redis'

require 'resque/stat'
require 'resque/logging'
require 'resque/job'
require 'resque/worker_registry'
require 'resque/process_coordinator'
require 'resque/worker'
require 'resque/plugin'
require 'resque/queue'
require 'resque/multi_queue'
require 'resque/coder'
require 'resque/json_coder'
require 'resque/hook_register'
require 'resque/instance'

require 'forwardable'

module Resque
  extend self

  # List of class name suffixes which will be considered to indicate
  # a class capable of performing work
  SUFFIXES = %w(Job Worker).freeze unless defined?(SUFFIXES)
end
