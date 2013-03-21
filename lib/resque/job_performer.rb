module Resque
  class JobPerformer
    def perform(payload_class, args, hooks)
      job = payload_class
      job_args = args || []
      job_was_performed = false

      # Execute before_perform hook. Abort the job gracefully if
      # Resque::Job::DontPerform is raised.
      begin
        hooks[:before].each do |hook|
          job.send(hook, *job_args)
        end
      rescue Job::DontPerform
        return false
      end

      # Execute the job. Do it in an around_perform hook if available.
      if hooks[:around].empty?
        job.perform(*job_args)
        job_was_performed = true
      else
        # We want to nest all around_perform plugins, with the last one
        # finally calling perform
        stack = hooks[:around].reverse.inject(nil) do |last_hook, hook|
          if last_hook
            lambda do
              job.send(hook, *job_args) { last_hook.call }
            end
          else
            lambda do
              job.send(hook, *job_args) do
                result = job.perform(*job_args)
                job_was_performed = true
                result
              end
            end
          end
        end
        stack.call
      end

      # Execute after_perform hook
      hooks[:after].each do |hook|
        job.send(hook, *job_args)
      end

      # Return true if the job was performed
      job_was_performed
    end
  end
end
