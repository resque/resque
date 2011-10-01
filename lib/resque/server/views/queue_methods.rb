module QueueMethods
  def subtabs
    Resque.queues if self.class.eql?(Resque::Views::Queues)
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

  def start
    params[:start].to_i
  end

  def end
    start + 20
  end

  def size
    redis_get_size(key)
  end

  def pagination?
    less_page? || more_page?
  end

  def less_page?
    start - 20 >= 0
  end

  def more_page?
    start + 20 <= size
  end

  def start_less
    start - 20
  end

  def start_more
    start + 20
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