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
    u "/queues/#{queue}/remove"
  end

  def pagination?
    true if size > 20
  end
  
  def less_page?
    actual_start > 0
  end
  
  def more_page?
    size > (actual_start + 20)
  end
  
  def start_less
    s = actual_start - 20
    if s >= 0
      s
    else
      0
    end
  end
  
  def start_more
    actual_start + 20
  end
  
  def start
    actual_start + 1
  end
  
  def actual_start
    params[:start].to_i or 0
  end

  def end
    s = actual_start + 20
    if s <= size
      s
    else
      size
    end
  end

  def size
    Resque.size(queue || self[:queue])
  end

  def jobs
    Resque.peek(queue, actual_start, 20).map do |job|
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