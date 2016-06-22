require 'test_helper'
require 'tmpdir'

describe "Resque::Worker" do
  class DummyLogger
    def initialize
      @rd, @wr = IO.pipe
    end

    def info(message); @wr << message << "\0"; end
    alias_method :debug, :info
    alias_method :warn,  :info
    alias_method :error, :info
    alias_method :fatal, :info

    def messages
      @wr.close
      @rd.read.split("\0")
    end
  end

  before do
    @worker = Resque::Worker.new(:jobs)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
  end

  after do
    @worker.kill_background_threads
  end

  it "can fail jobs" do
    Resque::Job.create(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, Resque::Failure.count
  end

  it "failed jobs report exception and message" do
    Resque::Job.create(:jobs, BadJobWithSyntaxError)
    @worker.work(0)
    assert_equal('SyntaxError', Resque::Failure.all['exception'])
    assert_equal('Extra Bad job!', Resque::Failure.all['error'])
  end

  it "does not allow exceptions from failure backend to escape" do
    job = Resque::Job.new(:jobs, {})
    with_failure_backend BadFailureBackend do
      @worker.perform job
    end
  end

  it "does not raise exception for completed jobs" do
    without_forking do
      @worker.work(0)
    end
    assert_equal 0, Resque::Failure.count
  end

  it "writes to ENV['PIDFILE'] when supplied and #prepare is called" do
    with_pidfile do
      tmpfile = Tempfile.new("test_pidfile")
      File.expects(:open).with(ENV["PIDFILE"], anything).returns tmpfile
      @worker.prepare
    end
  end

  it "daemonizes when ENV['BACKGROUND'] is supplied and #prepare is called" do
    if Process.respond_to?("daemon")
      Process.expects(:daemon)
      with_background do
        @worker.prepare
      end
    else
      skip("Process.daemon not supported; requires ruby >= 1.9")
    end
  end

  it "executes at_exit hooks when configured with run_at_exit_hooks" do
    tmpfile = File.join(Dir.tmpdir, "resque_at_exit_test_file")
    FileUtils.rm_f tmpfile

    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
      assert File.exist?(tmpfile), "The file '#{tmpfile}' does not exist"
      assert_equal "at_exit", File.open(tmpfile).read.strip
    else
      # ensure we actually fork
      Resque.redis.client.reconnect
      Resque::Job.create(:at_exit_jobs, AtExitJob, tmpfile)
      worker = Resque::Worker.new(:at_exit_jobs)
      worker.run_at_exit_hooks = true
      suppress_warnings do
        worker.work(0)
      end
      exit
    end

  end

  class ::RaiseExceptionOnFailure

    def self.on_failure_throw_exception(exception,*args)
      raise "The worker threw an exception"
    end

    def self.perform
      ""
    end
  end

  it "should not treat SystemExit as an exception in the child with run_at_exit_hooks == true" do
    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
    else
      # ensure we actually fork
      Resque.redis.client.reconnect
      Resque::Job.create(:not_failing_job, RaiseExceptionOnFailure)
      worker = Resque::Worker.new(:not_failing_job)
      worker.run_at_exit_hooks = true
      suppress_warnings do
        worker.work(0)
      end
      exit
    end
  end

  it "does not execute at_exit hooks by default" do
    tmpfile = File.join(Dir.tmpdir, "resque_at_exit_test_file")
    FileUtils.rm_f tmpfile

    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
      assert !File.exist?(tmpfile), "The file '#{tmpfile}' exists, at_exit hooks were run"
    else
      # ensure we actually fork
      Resque.redis.client.reconnect
      Resque::Job.create(:at_exit_jobs, AtExitJob, tmpfile)
      worker = Resque::Worker.new(:at_exit_jobs)
      suppress_warnings do
        worker.work(0)
      end
      exit
    end
  end

  it "does report failure for jobs with invalid payload" do
    job = Resque::Job.new(:jobs, { 'class' => 'NotAValidJobClass', 'args' => '' })
    @worker.perform job
    assert_equal 1, Resque::Failure.count, 'failure not reported'
  end

  it "register 'run_at' time on UTC timezone in ISO8601 format" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    now = Time.now.utc.iso8601
    @worker.working_on(job)
    assert_equal now, @worker.processing['run_at']
  end

  it "fails uncompleted jobs with DirtyExit by default on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    @worker.working_on(job)
    @worker.unregister_worker
    assert_equal 1, Resque::Failure.count
    assert_equal('Resque::DirtyExit', Resque::Failure.all['exception'])
  end

  it "fails uncompleted jobs with worker exception on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    @worker.working_on(job)
    @worker.unregister_worker(StandardError.new)
    assert_equal 1, Resque::Failure.count
    assert_equal('StandardError', Resque::Failure.all['exception'])
  end

  it "does not mask exception when timeout getting job metadata" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    @worker.working_on(job)
    Resque.data_store.redis.stubs(:get).raises(Redis::CannotConnectError)

    error_message = "Something bad happened"
    exception_caught = assert_raises Redis::CannotConnectError do
      @worker.unregister_worker(raised_exception(StandardError,error_message))
    end
    assert_match /StandardError/, exception_caught.message
    assert_match /#{error_message}/, exception_caught.message
    assert_match /Redis::CannotConnectError/, exception_caught.message
  end

  def raised_exception(klass,message)
    raise klass,message
  rescue Exception => ex
    ex
  end

  class ::SimpleJobWithFailureHandling
    def self.on_failure_record_failure(exception, *job_args)
      @@exception = exception
    end

    def self.exception
      @@exception
    end
  end

  it "fails uncompleted jobs on exit, and calls failure hook" do
    job = Resque::Job.new(:jobs, {'class' => 'SimpleJobWithFailureHandling', 'args' => ""})
    @worker.working_on(job)
    @worker.unregister_worker
    assert_equal 1, Resque::Failure.count
    assert(SimpleJobWithFailureHandling.exception.kind_of?(Resque::DirtyExit))
  end

  it "fails uncompleted jobs on exit and unregisters without erroring out and logs helpful message if error occurs during a failure hook" do
    Resque.logger = DummyLogger.new

    begin
      job = Resque::Job.new(:jobs, {'class' => 'BadJobWithOnFailureHookFail', 'args' => []})
      @worker.working_on(job)
      @worker.unregister_worker
      messages = Resque.logger.messages
    ensure
      reset_logger
    end
    assert_equal 1, Resque::Failure.count
    error_message = messages.first
    assert_match('Additional error (RuntimeError: This job is just so bad!)', error_message)
    assert_match('occurred in running failure hooks', error_message)
    assert_match('for job (Job{jobs} | BadJobWithOnFailureHookFail | [])', error_message)
    assert_match('Original error that caused job failure was RuntimeError: Resque::DirtyExit', error_message)
  end

  class ::SimpleFailingJob
    @@exception_count = 0

    def self.on_failure_record_failure(exception, *job_args)
      @@exception_count += 1
    end

    def self.exception_count
      @@exception_count
    end

    def self.perform
      raise Exception.new
    end
  end

  it "only calls failure hook once on exception" do
    job = Resque::Job.new(:jobs, {'class' => 'SimpleFailingJob', 'args' => ""})
    @worker.perform(job)
    assert_equal 1, Resque::Failure.count
    assert_equal 1, SimpleFailingJob.exception_count
  end

  it "can peek at failed jobs" do
    10.times { Resque::Job.create(:jobs, BadJob) }
    @worker.work(0)
    assert_equal 10, Resque::Failure.count

    assert_equal 10, Resque::Failure.all(0, 20).size
  end

  it "can clear failed jobs" do
    Resque::Job.create(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, Resque::Failure.count
    Resque::Failure.clear
    assert_equal 0, Resque::Failure.count
  end

  it "catches exceptional jobs" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)
    @worker.process
    @worker.process
    @worker.process
    assert_equal 2, Resque::Failure.count
  end

  it "supports setting the procline to have arbitrary prefixes and suffixes" do
    prefix = 'WORKER-TEST-PREFIX/'
    suffix = 'worker-test-suffix'
    ver = Resque::Version

    old_prefix = ENV['RESQUE_PROCLINE_PREFIX']
    ENV.delete('RESQUE_PROCLINE_PREFIX')
    old_procline = $0

    @worker.procline(suffix)
    assert_equal $0, "resque-#{ver}: #{suffix}"

    ENV['RESQUE_PROCLINE_PREFIX'] = prefix
    @worker.procline(suffix)
    assert_equal $0, "#{prefix}resque-#{ver}: #{suffix}"

    $0 = old_procline
    if old_prefix.nil?
      ENV.delete('RESQUE_PROCLINE_PREFIX')
    else
      ENV['RESQUE_PROCLINE_PREFIX'] = old_prefix
    end
  end

  it "strips whitespace from queue names" do
    queues = "critical, high, low".split(',')
    worker = Resque::Worker.new(*queues)
    assert_equal %w( critical high low ), worker.queues
  end

  it "can work on multiple queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)

    worker = Resque::Worker.new(:critical, :high)

    worker.process
    assert_equal 1, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)

    worker.process
    assert_equal 0, Resque.size(:high)
  end

  it "the queues method avoids unnecessary calls to smembers" do
    worker = Resque::Worker.new(:critical, :high)
    Resque.redis.expects(:smembers).at_most_once
    assert_equal ["critical", "high"], worker.queues
  end

  it "can work on all queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    @worker = Resque::Worker.new("*")
    @worker.work(0)

    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
  end

  it "can work with wildcard at the end of the list" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)
    Resque::Job.create(:beer, GoodJob)

    @worker = Resque::Worker.new(:critical, :high, "*")
    @worker.work(0)

    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
    assert_equal 0, Resque.size(:beer)
  end

  it "can work with wildcard at the middle of the list" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)
    Resque::Job.create(:beer, GoodJob)

    @worker = Resque::Worker.new(:critical, "*", :high)
    @worker.work(0)

    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
    assert_equal 0, Resque.size(:beer)
  end

  it "processes * queues in alphabetical order" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    processed_queues = []
    @worker = Resque::Worker.new("*")
    without_forking do
      @worker.work(0) do |job|
        processed_queues << job.queue
      end
    end

    assert_equal %w( jobs high critical blahblah ).sort, processed_queues
  end

  it "works with globs" do
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:test_one, GoodJob)
    Resque::Job.create(:test_two, GoodJob)

    @worker = Resque::Worker.new("test_*")
    @worker.work(0)

    assert_equal 1, Resque.size(:critical)
    assert_equal 0, Resque.size(:test_one)
    assert_equal 0, Resque.size(:test_two)
  end

  it "has a unique id" do
    assert_equal "#{`hostname`.chomp}:#{$$}:jobs", @worker.to_s
  end

  it "complains if no queues are given" do
    assert_raises Resque::NoQueueError do
      Resque::Worker.new
    end
  end

  it "fails if a job class has no `perform` method" do
    Resque::Job.create(:perform_less, Object)
    assert_equal 0, Resque::Failure.count

    @worker = Resque::Worker.new(:perform_less)
    @worker.work(0)

    assert_equal 1, Resque::Failure.count
  end

  it "inserts itself into the 'workers' list on startup" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert_equal @worker, Resque.workers[0]
      end
    end
  end

  it "removes itself from the 'workers' list on shutdown" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert_equal @worker, Resque.workers[0]
      end
    end

    assert_equal [], Resque.workers
  end

  it "removes worker with stringified id" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        worker_id = Resque.workers[0].to_s
        Resque.remove_worker(worker_id)
        assert_equal [], Resque.workers
      end
    end
  end

  it "records what it is working on" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        task = @worker.job
        assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
        assert task['run_at']
        assert_equal 'jobs', task['queue']
      end
    end
  end

  it "clears its status when not working on anything" do
    @worker.work(0)
    assert_equal Hash.new, @worker.job
  end

  it "knows when it is working" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert @worker.working?
      end
    end
  end

  it "knows when it is idle" do
    @worker.work(0)
    assert @worker.idle?
  end

  it "knows who is working" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert_equal [@worker], Resque.working
      end
    end
  end

  it "caches the current job iff reloading is disabled" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        first_instance = @worker.job
        second_instance = @worker.job
        refute_equal first_instance.object_id, second_instance.object_id

        first_instance = @worker.job(false)
        second_instance = @worker.job(false)
        assert_equal first_instance.object_id, second_instance.object_id
      end
    end
  end

  it "keeps track of how many jobs it has processed" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 3, @worker.processed
  end

  it "keeps track of how many failures it has seen" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 2, @worker.failed
  end

  it "stats are erased when the worker goes away" do
    @worker.work(0)
    assert_equal 0, @worker.processed
    assert_equal 0, @worker.failed
  end

  it "knows when it started" do
    time = Time.now
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert Time.parse(@worker.started) - time < 0.1
      end
    end
  end

  it "knows whether it exists or not" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        assert Resque::Worker.exists?(@worker)
        assert !Resque::Worker.exists?('blah-blah')
      end
    end
  end

  it "knows what host it's running on" do
    without_forking do
      blah_worker = nil
      Socket.stub :gethostname, 'blah-blah' do
        blah_worker = Resque::Worker.new(:jobs)
        blah_worker.register_worker
      end

      @worker.extend(AssertInWorkBlock).work(0) do
        assert Resque::Worker.exists?(blah_worker)
        assert_equal Resque::Worker.find(blah_worker).hostname, 'blah-blah'
      end
    end
  end

  it "sets $0 while working" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        prefix = ENV['RESQUE_PROCLINE_PREFIX']
        ver = Resque::Version
        assert_equal "#{prefix}resque-#{ver}: Processing jobs since #{Time.now.to_i} [SomeJob]", $0
      end
    end
  end

  it "can be found" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        found = Resque::Worker.find(@worker.to_s)

        # we ensure that the found ivar @pid is set to the correct value since
        # Resque::Worker#pid will use it instead of Process.pid if present
        assert_equal @worker.pid, found.instance_variable_get(:@pid)

        assert_equal @worker.to_s, found.to_s
        assert found.working?
        assert_equal @worker.job, found.job
      end
    end
  end

  it 'can find others' do
    without_forking do
      # inject fake worker
      other_worker = Resque::Worker.new(:other_jobs)
      other_worker.pid = 123456
      other_worker.register_worker

      begin
        @worker.extend(AssertInWorkBlock).work(0) do
          found = Resque::Worker.find(other_worker.to_s)
          assert_equal other_worker.to_s, found.to_s
          assert_equal other_worker.pid, found.pid
          assert !found.working?
          assert found.job.empty?
        end
      ensure
        other_worker.unregister_worker
      end
    end
  end

  it "doesn't find fakes" do
    without_forking do
      @worker.extend(AssertInWorkBlock).work(0) do
        found = Resque::Worker.find('blah-blah')
        assert_equal nil, found
      end
    end
  end

  it "doesn't write PID file when finding" do
    with_pidfile do
      File.expects(:open).never

      without_forking do
        @worker.work(0) do
          Resque::Worker.find(@worker.to_s)
        end
      end
    end
  end

  it "prunes dead workers with heartbeat older than prune interval" do
    now = Time.now

    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "bar:3:jobs")
    workerA.register_worker
    workerA.heartbeat!(now - Resque.prune_interval - 1)

    assert_equal 1, Resque.workers.size

    workerB = Resque::Worker.new(:jobs)
    workerB.instance_variable_set(:@to_s, "foo:5:jobs")
    workerB.register_worker
    workerB.heartbeat!(now)

    assert_equal 2, Resque.workers.size

    @worker.prune_dead_workers

    assert_equal 1, Resque.workers.size
  end

  it "does not prune workers that haven't set a heartbeat" do
    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "bar:3:jobs")
    workerA.register_worker

    assert_equal 1, Resque.workers.size

    @worker.prune_dead_workers

    assert_equal 1, Resque.workers.size
  end

  it "does return returns a valid time when asking for heartbeat" do
    workerA = Resque::Worker.new(:jobs)
    workerA.register_worker
    workerA.heartbeat!

    assert_instance_of Time, workerA.heartbeat
  end

  it "cleans up dead worker info on start (crash recovery)" do
    # first we fake out several dead workers
    # 1: matches queue and hostname; gets pruned.
    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "#{`hostname`.chomp}:1:jobs")
    workerA.register_worker
    workerA.heartbeat!

    # 2. matches queue but not hostname; no prune.
    workerB = Resque::Worker.new(:jobs)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}-foo:2:jobs")
    workerB.register_worker
    workerB.heartbeat!

    # 3. matches hostname but not queue; no prune.
    workerB = Resque::Worker.new(:high)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}:3:high")
    workerB.register_worker
    workerB.heartbeat!

    # 4. matches neither hostname nor queue; no prune.
    workerB = Resque::Worker.new(:high)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}-foo:4:high")
    workerB.register_worker
    workerB.heartbeat!

    assert_equal 4, Resque.workers.size

    # then we prune them
    @worker.work(0)

    worker_strings = Resque::Worker.all.map(&:to_s)

    assert_equal 3, Resque.workers.size

    # pruned
    assert !worker_strings.include?("#{`hostname`.chomp}:1:jobs")

    # not pruned
    assert worker_strings.include?("#{`hostname`.chomp}-foo:2:jobs")
    assert worker_strings.include?("#{`hostname`.chomp}:3:high")
    assert worker_strings.include?("#{`hostname`.chomp}-foo:4:high")
  end

  it "worker_pids returns pids" do
    @worker.work(0)
    known_workers = @worker.worker_pids
    assert !known_workers.empty?
  end

  it "Processed jobs count" do
    @worker.work(0)
    assert_equal 1, Resque.info[:processed]
  end

  it "Will call a before_first_fork hook only once" do
    $BEFORE_FORK_CALLED = 0
    Resque.before_first_fork = Proc.new { $BEFORE_FORK_CALLED += 1 }
    workerA = Resque::Worker.new(:jobs)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')

    assert_equal 0, $BEFORE_FORK_CALLED

    workerA.work(0)
    assert_equal 1, $BEFORE_FORK_CALLED

    #Verify it's only run once.
    workerA.work(0)
    assert_equal 1, $BEFORE_FORK_CALLED
  end

  it "Will call a before_pause hook before pausing" do
    $BEFORE_PAUSE_CALLED = 0
    $WORKER_NAME = nil
    Resque.before_pause = Proc.new { |w| $BEFORE_PAUSE_CALLED += 1; $WORKER_NAME = w.to_s; }
    workerA = Resque::Worker.new(:jobs)

    assert_equal 0, $BEFORE_PAUSE_CALLED
    workerA.pause_processing
    assert_equal 1, $BEFORE_PAUSE_CALLED
    assert_equal workerA.to_s, $WORKER_NAME
  end

  it "Will call a after_pause hook after pausing" do
    $AFTER_PAUSE_CALLED = 0
    $WORKER_NAME = nil
    Resque.after_pause = Proc.new { |w| $AFTER_PAUSE_CALLED += 1; $WORKER_NAME = w.to_s; }
    workerA = Resque::Worker.new(:jobs)

    assert_equal 0, $AFTER_PAUSE_CALLED
    workerA.unpause_processing
    assert_equal 1, $AFTER_PAUSE_CALLED
    assert_equal workerA.to_s, $WORKER_NAME
  end

  it "Will call a before_fork hook before forking" do
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$BEFORE_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert $BEFORE_FORK_CALLED
  end

  it "Will not call a before_fork hook when the worker cannot fork" do
    without_forking do
      $BEFORE_FORK_CALLED = false
      Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
      workerA = Resque::Worker.new(:jobs)

      assert !$BEFORE_FORK_CALLED, "before_fork should not have been called before job runs"
      Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
      workerA.work(0)
      assert !$BEFORE_FORK_CALLED, "before_fork should not have been called after job runs"
    end
  end

  it "Will not call a before_fork hook when forking set to false" do
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called before job runs"
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    # This sets ENV['FORK_PER_JOB'] = 'false' and then restores it
    without_forking do
      workerA.work(0)
    end
    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called after job runs"
  end

  it "setting verbose to true" do
    @worker.verbose = true

    assert @worker.verbose
    assert !@worker.very_verbose
  end

  it "setting verbose to false" do
    @worker.verbose = false

    assert !@worker.verbose
    assert !@worker.very_verbose
  end

  it "setting very_verbose to true" do
    @worker.very_verbose = true

    assert !@worker.verbose
    assert @worker.very_verbose
  end

  it "setting setting verbose to true and then very_verbose to false" do
    @worker.very_verbose = true
    @worker.verbose      = true
    @worker.very_verbose = false

    assert @worker.verbose
    assert !@worker.very_verbose
  end

  it "verbose prints out logs" do
    messages        = StringIO.new
    Resque.logger   = Logger.new(messages)
    @worker.verbose = true

    @worker.log("omghi mom")

    assert_equal "*** omghi mom\n", messages.string
  end

  it "unsetting verbose works" do
    messages        = StringIO.new
    Resque.logger   = Logger.new(messages)
    @worker.verbose = true
    @worker.verbose = false

    @worker.log("omghi mom")

    assert_equal "", messages.string
  end

  it "very verbose works in the afternoon" do
    messages        = StringIO.new
    Resque.logger   = Logger.new(messages)

    begin
      require 'time'
      last_puts = ""
      Time.fake_time = Time.parse("15:44:33 2011-03-02")

      @worker.very_verbose = true
      @worker.log("some log text")

      assert_match /\*\* \[15:44:33 2011-03-02\] \d+: some log text/, messages.string
    ensure
      Time.fake_time = nil
    end
  end

  it "keeps a custom logger state after a new worker is instantiated if there is no verbose options" do
    messages                = StringIO.new
    custom_logger           = Logger.new(messages)
    custom_logger.level     = Logger::FATAL
    custom_formatter        = proc do |severity, datetime, progname, msg|
      formatter.call(severity, datetime, progname, msg.dump)
    end
    custom_logger.formatter = custom_formatter

    Resque.logger = custom_logger

    ENV.delete 'VERBOSE'
    ENV.delete 'VVERBOSE'
    @worker = Resque::Worker.new(:jobs)

    assert_equal custom_logger, Resque.logger
    assert_equal Logger::FATAL, Resque.logger.level
    assert_equal custom_formatter, Resque.logger.formatter
  end

  it "won't fork if ENV['FORK_PER_JOB'] is false" do
    old_fork_per_job = ENV["FORK_PER_JOB"]
    begin
      ENV["FORK_PER_JOB"] = 'false'
      assert_equal false, Resque::Worker.new(:jobs).fork_per_job?
    ensure
      ENV["FORK_PER_JOB"] = old_fork_per_job
    end
  end

  it "Will call an after_fork hook after forking" do
    begin
      pipe_rd, pipe_wr = IO.pipe

      Resque.after_fork = Proc.new { pipe_wr.write('hey') }
      workerA = Resque::Worker.new(:jobs)

      Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
      workerA.work(0)

      assert_equal('hey', pipe_rd.read_nonblock(3))
    ensure
      pipe_rd.close
      pipe_wr.close
    end
  end

  it "Will not call an after_fork hook when the worker won't fork" do
    without_forking do
      $AFTER_FORK_CALLED = false
      Resque.after_fork = Proc.new { $AFTER_FORK_CALLED = true }
      workerA = Resque::Worker.new(:jobs)

      assert !$AFTER_FORK_CALLED
      Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
      workerA.work(0)
      assert !$AFTER_FORK_CALLED
    end
  end

  it "returns PID of running process" do
    assert_equal @worker.to_s.split(":")[1].to_i, @worker.pid
  end

  it "requeue failed queue" do
    queue = 'good_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => 'some_job', :payload => {'class' => 'SomeJob'})
    Resque::Failure.requeue_queue(queue)
    assert Resque::Failure.all(0).has_key?('retried_at')
    assert !Resque::Failure.all(1).has_key?('retried_at')
  end

  it "remove failed queue" do
    queue = 'good_job'
    queue2 = 'some_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue2), :queue => queue2, :payload => {'class' => 'SomeJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.remove_queue(queue)
    assert_equal queue2, Resque::Failure.all(0)['queue']
    assert_equal 1, Resque::Failure.count
  end

  it "no reconnects to redis when not forking" do
    original_connection = Resque.redis.client.connection.instance_variable_get("@sock")
    without_forking do
      @worker.work(0)
    end
    assert_equal original_connection, Resque.redis.client.connection.instance_variable_get("@sock")
  end

  it "logs errors with the correct logging level" do
    messages = StringIO.new
    Resque.logger = Logger.new(messages)
    @worker.report_failed_job(BadJobWithSyntaxError, SyntaxError)

    assert_equal 0, messages.string.scan(/INFO/).count
    assert_equal 2, messages.string.scan(/ERROR/).count
  end

  it "logs info with the correct logging level" do
    messages = StringIO.new
    Resque.logger = Logger.new(messages)
    @worker.shutdown

    assert_equal 1, messages.string.scan(/INFO/).count
    assert_equal 0, messages.string.scan(/ERROR/).count
  end

  class CounterJob
    class << self
      attr_accessor :perform_count
    end
    self.perform_count = 0

    def self.perform
      self.perform_count += 1
    end
  end

  it "runs jobs without forking if fork isn't implemented" do
    nil while @worker.reserve # empty queue
    @worker.expects(:fork).raises(NotImplementedError)
    Resque.enqueue_to(:jobs, CounterJob)

    begin
      @worker.work(0)
      assert_equal 1, CounterJob.perform_count
      assert_equal false, @worker.fork_per_job?
    ensure
      CounterJob.perform_count = 0
    end
  end

  if !defined?(RUBY_ENGINE) || RUBY_ENGINE != "jruby"
    class ForkResultJob
      @queue = :jobs

      def self.perform_with_result(worker, &block)
        @rd, @wr = IO.pipe
        @block = block
        Resque.enqueue(self)
        worker.work(0)
        @wr.close
        Marshal.load(@rd.read)
      ensure
        @rd, @wr, @block = nil
      end

      def self.perform
        result = @block.call
        @wr.write(Marshal.dump(result))
        @wr.close
      end
    end

    def run_in_job(&block)
      ForkResultJob.perform_with_result(@worker, &block)
    end

    it "reconnects to redis after fork" do
      original_connection = Resque.redis.client.connection.instance_variable_get("@sock").object_id
      new_connection = run_in_job do
        Resque.redis.client.connection.instance_variable_get("@sock").object_id
      end
      refute_equal original_connection, new_connection
    end

    it "tries to reconnect three times before giving up and the failure does not unregister the parent" do
      @worker.redis.client.stubs(:reconnect).raises(Redis::BaseConnectionError)
      @worker.stubs(:sleep)

      Resque.logger = DummyLogger.new
      @worker.work(0)
      messages = Resque.logger.messages

      assert_equal 3, messages.grep(/retrying/).count
      assert_equal 1, messages.grep(/quitting/).count
      assert_equal 0, messages.grep(/Failed to start worker/).count
      assert_equal 1, messages.grep(/Redis::BaseConnectionError: Redis::BaseConnectionError/).count
    end

    it "tries to reconnect three times before giving up" do
      captured_worker = nil

      @worker.redis.client.stubs(:reconnect).raises(Redis::BaseConnectionError)
      @worker.stubs(:sleep)

      Resque.logger = DummyLogger.new
      @worker.work(0)
      messages = Resque.logger.messages

      assert_equal 3, messages.grep(/retrying/).count
      assert_equal 1, messages.grep(/quitting/).count
    end

    class SuicidalJob
      @queue = :jobs

      def self.perform
        Process.kill('KILL', Process.pid)
      end

      def self.on_failure_store_exception(exc, *args)
        @@failure_exception = exc
      end
    end

    it "will notify failure hooks when a job is killed by a signal" do
      Resque.enqueue(SuicidalJob)
      suppress_warnings do
        @worker.work(0)
      end
      assert_equal Resque::DirtyExit, SuicidalJob.send(:class_variable_get, :@@failure_exception).class
    end
  end
end
