# frozen_string_literal: true

require "active_job/queue_adapters/resque_adapter"
ActiveJob::Base.queue_adapter = :resque
