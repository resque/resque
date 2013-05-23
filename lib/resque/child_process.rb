require 'resque/child_processor/basic'
require 'resque/child_processor/fork'

module Resque
  # A child process processes a single job. It is created by a Resque Worker.
  module ChildProcess

    def self.create(worker)
      if worker.will_fork?
        ChildProcessor::Fork.new(worker)
      else
        ChildProcessor::Basic.new(worker)
      end
    end

  end
end
