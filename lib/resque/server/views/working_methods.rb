module WorkingMethods
  include WorkerList
  # If we're only looking at a single worker, return it as the
  # context.
  def single_worker?
    id = params[:id]
    if id && (worker = Resque::Worker.find(id)) && worker.job
      worker
    end
  end

  # A sorted array of workers currently working.
  def working
    Resque.working.
    sort_by { |w| w.job['run_at'] ? w.job['run_at'] : '' }.
    reject { |w| w.idle? }
  end

  # Is no one working?
  def none_working?
    working.empty?
  end

  # Does this context have a job?
  def no_job
    !self[:job]
  end

  # The number of workers currently working.
  def workers_working
    Resque.working.size
  end

  # The number of workers total.
  def workers_total
    Resque.workers.size
  end

  # TODO: Mustache method_missing this guy
  def job_queue
    self[:queue]
  end

  # URL of the current job's queue
  def job_queue_url
    u "/queues/#{job_queue}"
  end
end