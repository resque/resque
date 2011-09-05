module QueueMethods
  def subtabs
    Resque.queues
  end

  def queues?
    !queue?
  end

  def queues
    Resque.queues.sort_by { |q| q.to_s }.map do |queue|
      { :queue => queue }
    end
  end

  def queue?
    queue && { :queue => queue }
  end

  def queue
    params[:id]
  end

  def queue_url
    u "queues/#{self[:queue]}"
  end

  def remove_queue_url
    u "/queues/#{queue}"
  end

  def start
    params[:start].to_i
  end

  def end
    start + 20
  end

  def size
    Resque.size(queue || self[:queue])
  end

  def jobs
    Resque.peek(queue, start, 20).map do |job|
      job.merge('args' => job['args'].inspect)
    end
  end

  def no_jobs
    jobs.empty?
  end

  def failure_class
    failed_count.zero? ? :failed : :failure
  end

  def failed_count
    Resque::Failure.count
  end

  def failed_url
    u :failed
  end
end