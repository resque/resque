module WorkerList
  def state_icon
    state = self[:state]
    %(<img src="#{u(state)}.png" alt="#{state}" title="#{state}">)
  end

  # If we're not looking at a single worker, we're looking at all
  # fo them.
  def all_workers?
    !params[:id]
  end

  # Host where the current worker lives.
  def worker_host
    worker_parts[0]
  end

  # PID of the current worker.
  def worker_pid
    worker_parts[1]
  end

  # Queues the current worker is concerned with.
  def worker_queues
    worker_parts[2..-1]
  end

  # The current worker's name split into three parts:
  # [ host, pid, queues ]
  def worker_parts
    self[:to_s].split(':')
  end

  # Worker URL of the current worker
  def worker_url
    u "/workers/#{self[:to_s]}"
  end

  # Working URL of the current working
  def working_url
    u "/working/#{self[:to_s]}"
  end
end