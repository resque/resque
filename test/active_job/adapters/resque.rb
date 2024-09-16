# frozen_string_literal: true

require "resque/active_job_extension"
ActiveJob::Base.queue_adapter = :resque
