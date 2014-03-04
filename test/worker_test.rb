require 'test_helper'
require 'tmpdir'

context "Resque::Worker" do
  setup do
    Resque.redis.flushall

    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil

    @worker = Resque::Worker.new(:jobs)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
  end

  test "can fail jobs" do
    Resque::Job.create(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, Resque::Failure.count
  end

  test "failed jobs report exception and message" do
    Resque::Job.create(:jobs, BadJobWithSyntaxError)
    @worker.work(0)
    assert_equal('SyntaxError', Resque::Failure.all['exception'])
    assert_equal('Extra Bad job!', Resque::Failure.all['error'])
  end

  test "does not allow exceptions from failure backend to escape" do
    job = Resque::Job.new(:jobs, {})
    with_failure_backend BadFailureBackend do
      @worker.perform job
    end
  end

  test "does not raise exception for completed jobs" do
    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
      assert_equal 0, Resque::Failure.count
    else
      # ensure we actually fork
      $TESTING = false
      Resque.redis.client.reconnect
      worker = Resque::Worker.new(:jobs)
      suppress_warnings do
        worker.work(0)
      end
      exit
    end
  end

  test "executes at_exit hooks when configured with run_at_exit_hooks" do
    tmpfile = File.join(Dir.tmpdir, "resque_at_exit_test_file")
    FileUtils.rm_f tmpfile

    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
      assert File.exist?(tmpfile), "The file '#{tmpfile}' does not exist"
      assert_equal "at_exit", File.open(tmpfile).read.strip
    else
      # ensure we actually fork
      $TESTING = false
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

    def self.on_failure_trhow_exception(exception,*args)
      $TESTING = true
      raise "The worker threw an exception"
    end

    def self.perform
      ""
    end
  end

  test "should not treat SystemExit as an exception in the child with run_at_exit_hooks == true" do

    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
    else
      # ensure we actually fork
      $TESTING = false
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


  test "does not execute at_exit hooks by default" do
    tmpfile = File.join(Dir.tmpdir, "resque_at_exit_test_file")
    FileUtils.rm_f tmpfile

    if worker_pid = Kernel.fork
      Process.waitpid(worker_pid)
      assert !File.exist?(tmpfile), "The file '#{tmpfile}' exists, at_exit hooks were run"
    else
      # ensure we actually fork
      $TESTING = false
      Resque.redis.client.reconnect
      Resque::Job.create(:at_exit_jobs, AtExitJob, tmpfile)
      worker = Resque::Worker.new(:at_exit_jobs)
      suppress_warnings do
        worker.work(0)
      end
      exit
    end

  end

  test "does report failure for jobs with invalid payload" do
    job = Resque::Job.new(:jobs, { 'class' => 'NotAValidJobClass', 'args' => '' })
    @worker.perform job
    assert_equal 1, Resque::Failure.count, 'failure not reported'
  end

  test "register 'run_at' time on UTC timezone in ISO8601 format" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    now = Time.now.utc.iso8601
    @worker.working_on(job)
    assert_equal now, @worker.processing['run_at']
  end

  test "fails uncompleted jobs with DirtyExit by default on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    @worker.working_on(job)
    @worker.unregister_worker
    assert_equal 1, Resque::Failure.count
    assert_equal('Resque::DirtyExit', Resque::Failure.all['exception'])
  end

  test "fails uncompleted jobs with worker exception on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    @worker.working_on(job)
    @worker.unregister_worker(StandardError.new)
    assert_equal 1, Resque::Failure.count
    assert_equal('StandardError', Resque::Failure.all['exception'])
  end

  class ::SimpleJobWithFailureHandling
    def self.on_failure_record_failure(exception, *job_args)
      @@exception = exception
    end

    def self.exception
      @@exception
    end
  end

  test "fails uncompleted jobs on exit, and calls failure hook" do
    job = Resque::Job.new(:jobs, {'class' => 'SimpleJobWithFailureHandling', 'args' => ""})
    @worker.working_on(job)
    @worker.unregister_worker
    assert_equal 1, Resque::Failure.count
    assert(SimpleJobWithFailureHandling.exception.kind_of?(Resque::DirtyExit))
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

  test "only calls failure hook once on exception" do
    job = Resque::Job.new(:jobs, {'class' => 'SimpleFailingJob', 'args' => ""})
    @worker.perform(job)
    assert_equal 1, Resque::Failure.count
    assert_equal 1, SimpleFailingJob.exception_count
  end

  test "can peek at failed jobs" do
    10.times { Resque::Job.create(:jobs, BadJob) }
    @worker.work(0)
    assert_equal 10, Resque::Failure.count

    assert_equal 10, Resque::Failure.all(0, 20).size
  end

  test "can clear failed jobs" do
    Resque::Job.create(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, Resque::Failure.count
    Resque::Failure.clear
    assert_equal 0, Resque::Failure.count
  end

  test "catches exceptional jobs" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)
    @worker.process
    @worker.process
    @worker.process
    assert_equal 2, Resque::Failure.count
  end

  test "strips whitespace from queue names" do
    queues = "critical, high, low".split(',')
    worker = Resque::Worker.new(*queues)
    assert_equal %w( critical high low ), worker.queues
  end

  test "can work on multiple queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)

    worker = Resque::Worker.new(:critical, :high)

    worker.process
    assert_equal 1, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)

    worker.process
    assert_equal 0, Resque.size(:high)
  end

  test "can work on all queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    worker = Resque::Worker.new("*")

    worker.work(0)
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
  end

  test "can work with wildcard at the end of the list" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)
    Resque::Job.create(:beer, GoodJob)

    worker = Resque::Worker.new(:critical, :high, "*")

    worker.work(0)
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
    assert_equal 0, Resque.size(:beer)
  end

  test "can work with wildcard at the middle of the list" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)
    Resque::Job.create(:beer, GoodJob)

    worker = Resque::Worker.new(:critical, "*", :high)

    worker.work(0)
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
    assert_equal 0, Resque.size(:beer)
  end

  test "processes * queues in alphabetical order" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    worker = Resque::Worker.new("*")
    processed_queues = []

    worker.work(0) do |job|
      processed_queues << job.queue
    end

    assert_equal %w( jobs high critical blahblah ).sort, processed_queues
  end

  test "works with globs" do
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:test_one, GoodJob)
    Resque::Job.create(:test_two, GoodJob)

    worker = Resque::Worker.new("test_*")

    worker.work(0)
    assert_equal 1, Resque.size(:critical)
    assert_equal 0, Resque.size(:test_one)
    assert_equal 0, Resque.size(:test_two)
  end

  test "has a unique id" do
    assert_equal "#{`hostname`.chomp}:#{$$}:jobs", @worker.to_s
  end

  test "complains if no queues are given" do
    assert_raise Resque::NoQueueError do
      Resque::Worker.new
    end
  end

  test "fails if a job class has no `perform` method" do
    worker = Resque::Worker.new(:perform_less)
    Resque::Job.create(:perform_less, Object)

    assert_equal 0, Resque::Failure.count
    worker.work(0)
    assert_equal 1, Resque::Failure.count
  end

  test "inserts itself into the 'workers' list on startup" do
    @worker.extend(AssertInWorkBlock).work(0) do
      assert_equal @worker, Resque.workers[0]
    end
  end

  test "removes itself from the 'workers' list on shutdown" do
    @worker.extend(AssertInWorkBlock).work(0) do
      assert_equal @worker, Resque.workers[0]
    end

    assert_equal [], Resque.workers
  end

  test "removes worker with stringified id" do
    @worker.extend(AssertInWorkBlock).work(0) do
      worker_id = Resque.workers[0].to_s
      Resque.remove_worker(worker_id)
      assert_equal [], Resque.workers
    end
  end

  test "records what it is working on" do
    @worker.extend(AssertInWorkBlock).work(0) do
      task = @worker.job
      assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
      assert task['run_at']
      assert_equal 'jobs', task['queue']
    end
  end

  test "clears its status when not working on anything" do
    @worker.work(0)
    assert_equal Hash.new, @worker.job
  end

  test "knows when it is working" do
    @worker.extend(AssertInWorkBlock).work(0) do
      assert @worker.working?
    end
  end

  test "knows when it is idle" do
    @worker.work(0)
    assert @worker.idle?
  end

  test "knows who is working" do
    @worker.extend(AssertInWorkBlock).work(0) do
      assert_equal [@worker], Resque.working
    end
  end

  test "keeps track of how many jobs it has processed" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 3, @worker.processed
  end

  test "keeps track of how many failures it has seen" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 2, @worker.failed
  end

  test "stats are erased when the worker goes away" do
    @worker.work(0)
    assert_equal 0, @worker.processed
    assert_equal 0, @worker.failed
  end

  test "knows when it started" do
    time = Time.now
    @worker.extend(AssertInWorkBlock).work(0) do
      assert Time.parse(@worker.started) - time < 0.1
    end
  end

  test "knows whether it exists or not" do
    @worker.extend(AssertInWorkBlock).work(0) do
      assert Resque::Worker.exists?(@worker)
      assert !Resque::Worker.exists?('blah-blah')
    end
  end

  test "sets $0 while working" do
    @worker.extend(AssertInWorkBlock).work(0) do
      ver = Resque::Version
      assert_equal "resque-#{ver}: Processing jobs since #{Time.now.to_i} [SomeJob]", $0
    end
  end

  test "can be found" do
    @worker.extend(AssertInWorkBlock).work(0) do
      found = Resque::Worker.find(@worker.to_s)
      assert_equal @worker.to_s, found.to_s
      assert found.working?
      assert_equal @worker.job, found.job
    end
  end

  test "doesn't find fakes" do
    @worker.extend(AssertInWorkBlock).work(0) do
      found = Resque::Worker.find('blah-blah')
      assert_equal nil, found
    end
  end

  test "cleans up dead worker info on start (crash recovery)" do
    # first we fake out several dead workers
    # 1: matches queue and hostname; gets pruned.
    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "#{`hostname`.chomp}:1:jobs")
    workerA.register_worker

    # 2. matches queue but not hostname; no prune.
    workerB = Resque::Worker.new(:jobs)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}-foo:2:jobs")
    workerB.register_worker

    # 3. matches hostname but not queue; no prune.
    workerB = Resque::Worker.new(:high)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}:3:high")
    workerB.register_worker

    # 4. matches neither hostname nor queue; no prune.
    workerB = Resque::Worker.new(:high)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}-foo:4:high")
    workerB.register_worker

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

  test "worker_pids returns pids" do
    known_workers = @worker.worker_pids
    assert !known_workers.empty?
  end

  test "Processed jobs count" do
    @worker.work(0)
    assert_equal 1, Resque.info[:processed]
  end

  test "Will call a before_first_fork hook only once" do
    Resque.redis.flushall
    $BEFORE_FORK_CALLED = 0
    Resque.before_first_fork = Proc.new { $BEFORE_FORK_CALLED += 1 }
    workerA = Resque::Worker.new(:jobs)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')

    assert_equal 0, $BEFORE_FORK_CALLED

    workerA.work(0)
    assert_equal 1, $BEFORE_FORK_CALLED

    # TODO: Verify it's only run once. Not easy.
#     workerA.work(0)
#     assert_equal 1, $BEFORE_FORK_CALLED
  end

  test "Will call a before_fork hook before forking" do
    Resque.redis.flushall
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$BEFORE_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert $BEFORE_FORK_CALLED
  end

  test "Will not call a before_fork hook when the worker can't fork" do
    Resque.redis.flushall
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)
    workerA.cant_fork = true

    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called before job runs"
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called after job runs"
  end

  test "setting verbose to true" do
    @worker.verbose = true

    assert @worker.verbose
    assert !@worker.very_verbose
  end

  test "setting verbose to false" do
    @worker.verbose = false

    assert !@worker.verbose
    assert !@worker.very_verbose
  end

  test "setting very_verbose to true" do
    @worker.very_verbose = true

    assert !@worker.verbose
    assert @worker.very_verbose
  end

  test "setting setting verbose to true and then very_verbose to false" do
    @worker.very_verbose = true
    @worker.verbose      = true
    @worker.very_verbose = false

    assert @worker.verbose
    assert !@worker.very_verbose
  end

  test "verbose prints out logs" do
    messages        = StringIO.new
    Resque.logger   = Logger.new(messages)
    @worker.verbose = true

    begin
      @worker.log("omghi mom")
    ensure
      reset_logger
    end

    assert_equal "*** omghi mom\n", messages.string
  end

  test "unsetting verbose works" do
    messages        = StringIO.new
    Resque.logger   = Logger.new(messages)
    @worker.verbose = true
    @worker.verbose = false

    begin
      @worker.log("omghi mom")
    ensure
      reset_logger
    end

    assert_equal "", messages.string
  end

  test "very verbose works in the afternoon" do
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
      reset_logger
    end
  end

  test "won't fork if ENV['FORK_PER_JOB'] is false" do
    begin
      $TESTING = false
      workerA = Resque::Worker.new(:jobs)

      if workerA.will_fork?
        begin
          ENV["FORK_PER_JOB"] = 'false'
          assert !workerA.will_fork?
        ensure
          ENV["FORK_PER_JOB"] = 'true'
        end
      end
    ensure
      $TESTING = true
    end
  end

  test "Will call an after_fork hook if we're forking" do
    Resque.redis.flushall
    $AFTER_FORK_CALLED = false
    Resque.after_fork = Proc.new { $AFTER_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$AFTER_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert $AFTER_FORK_CALLED == workerA.will_fork?
  end

  test "Will not call an after_fork hook when the worker can't fork" do
    Resque.redis.flushall
    $AFTER_FORK_CALLED = false
    Resque.after_fork = Proc.new { $AFTER_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)
    workerA.cant_fork = true

    assert !$AFTER_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert !$AFTER_FORK_CALLED
  end

  test "returns PID of running process" do
    assert_equal @worker.to_s.split(":")[1].to_i, @worker.pid
  end

  test "requeue failed queue" do
    queue = 'good_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => 'some_job', :payload => {'class' => 'SomeJob'})
    Resque::Failure.requeue_queue(queue)
    assert Resque::Failure.all(0).has_key?('retried_at')
    assert !Resque::Failure.all(1).has_key?('retried_at')
  end

  test "remove failed queue" do
    queue = 'good_job'
    queue2 = 'some_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue2), :queue => queue2, :payload => {'class' => 'SomeJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.remove_queue(queue)
    assert_equal queue2, Resque::Failure.all(0)['queue']
    assert_equal 1, Resque::Failure.count
  end

  test "reconnects to redis after fork" do
    original_connection = Resque.redis.client.connection.instance_variable_get("@sock")
    @worker.work(0)
    assert_not_equal original_connection, Resque.redis.client.connection.instance_variable_get("@sock")
  end

  test "tries to reconnect three times before giving up and the failure does not unregister the parent" do
    begin
      class Redis::Client
        alias_method :original_reconnect, :reconnect

        def reconnect
          raise Redis::BaseConnectionError
        end
      end

      class Resque::Worker
        alias_method :original_sleep, :sleep

        def sleep(duration = nil)
          # noop
        end
      end

      stdout, stderr = capture_io do
        Resque.logger = Logger.new($stdout)
        @worker.work(0)
      end

      assert_equal 3, stdout.scan(/retrying/).count
      assert_equal 1, stdout.scan(/quitting/).count
      assert_equal 0, stdout.scan(/Failed to start worker/).count
      assert_equal 1, stdout.scan(/Redis::BaseConnectionError: Redis::BaseConnectionError/).count

    ensure
      class Redis::Client
        alias_method :reconnect, :original_reconnect
      end

      class Resque::Worker
        alias_method :sleep, :original_sleep
      end
    end
  end

  test "will call before_pause before it is paused" do
    before_pause_called = false
    captured_worker = nil
    begin
      class Redis::Client
        alias_method :original_reconnect, :reconnect

        def reconnect
          raise Redis::BaseConnectionError
        end
      end

      class Resque::Worker
        alias_method :original_sleep, :sleep

        def sleep(duration = nil)
          # noop
        end
      end

      class DummyLogger
        attr_reader :messages

        def initialize
          @messages = []
        end

        def info(message); @messages << message; end
        alias_method :debug, :info
        alias_method :warn,  :info
        alias_method :error, :info
        alias_method :fatal, :info
      end

      Resque.logger = DummyLogger.new
      begin
        @worker.work(0)
        messages = Resque.logger.messages
      ensure
        reset_logger
      end

      assert_equal 3, messages.grep(/retrying/).count
      assert_equal 1, messages.grep(/quitting/).count
    ensure
      class Redis::Client
        alias_method :reconnect, :original_reconnect
      end

      class Resque::Worker
        alias_method :sleep, :original_sleep
      end
    end
  end

  if !defined?(RUBY_ENGINE) || defined?(RUBY_ENGINE) && RUBY_ENGINE != "jruby"
    test "old signal handling is the default" do
      rescue_time = nil

      begin
        class LongRunningJob
          @queue = :long_running_job

          def self.perform( run_time, rescue_time=nil )
            Resque.redis.client.reconnect # get its own connection
            Resque.redis.rpush( 'sigterm-test:start', Process.pid )
            sleep run_time
            Resque.redis.rpush( 'sigterm-test:result', 'Finished Normally' )
          rescue Resque::TermException => e
            Resque.redis.rpush( 'sigterm-test:result', %Q(Caught SignalException: #{e.inspect}))
            sleep rescue_time unless rescue_time.nil?
          ensure
            puts 'fuuuu'
            Resque.redis.rpush( 'sigterm-test:final', 'exiting.' )
          end
        end

        Resque.enqueue( LongRunningJob, 5, rescue_time )

        worker_pid = Kernel.fork do
          # ensure we actually fork
          $TESTING = false
          # reconnect since we just forked
          Resque.redis.client.reconnect

          worker = Resque::Worker.new(:long_running_job)

          suppress_warnings do
            worker.work(0)
          end
          exit!
        end

        # ensure the worker is started
        start_status = Resque.redis.blpop( 'sigterm-test:start', 5 )
        assert_not_nil start_status
        child_pid = start_status[1].to_i
        assert_operator child_pid, :>, 0

        # send signal to abort the worker
        Process.kill('TERM', worker_pid)
        Process.waitpid(worker_pid)

        # wait to see how it all came down
        result = Resque.redis.blpop( 'sigterm-test:result', 5 )
        assert_nil result

        # ensure that the child pid is no longer running
        child_not_running = `ps -p #{child_pid.to_s} -o pid=`.empty?
        assert child_not_running
      ensure
        remaining_keys = Resque.redis.keys('sigterm-test:*') || []
        Resque.redis.del(*remaining_keys) unless remaining_keys.empty?
      end
    end
  end

  if !defined?(RUBY_ENGINE) || defined?(RUBY_ENGINE) && RUBY_ENGINE != "jruby"
    [SignalException, Resque::TermException].each do |exception|
      {
        'cleanup occurs in allotted time' => nil,
        'cleanup takes too long' => 2
      }.each do |scenario,rescue_time|
        test "SIGTERM when #{scenario} while catching #{exception}" do
          begin
            eval("class LongRunningJob; @@exception = #{exception}; end")
            class LongRunningJob
              @queue = :long_running_job

              def self.perform( run_time, rescue_time=nil )
                Resque.redis.client.reconnect # get its own connection
                Resque.redis.rpush( 'sigterm-test:start', Process.pid )
                sleep run_time
                Resque.redis.rpush( 'sigterm-test:result', 'Finished Normally' )
              rescue @@exception => e
                Resque.redis.rpush( 'sigterm-test:result', %Q(Caught SignalException: #{e.inspect}))
                sleep rescue_time unless rescue_time.nil?
              ensure
                Resque.redis.rpush( 'sigterm-test:final', 'exiting.' )
              end
            end

            Resque.enqueue( LongRunningJob, 5, rescue_time )

            worker_pid = Kernel.fork do
              # ensure we actually fork
              $TESTING = false
              # reconnect since we just forked
              Resque.redis.client.reconnect

              worker = Resque::Worker.new(:long_running_job)
              worker.term_timeout = 1
              worker.term_child = 1

              worker.work(0)
              exit!
            end

            # ensure the worker is started
            start_status = Resque.redis.blpop( 'sigterm-test:start', 5 )
            assert_not_nil start_status
            child_pid = start_status[1].to_i
            assert_operator child_pid, :>, 0

            # send signal to abort the worker
            Process.kill('TERM', worker_pid)
            Process.waitpid(worker_pid)

            # wait to see how it all came down
            result = Resque.redis.blpop( 'sigterm-test:result', 5 )
            assert_not_nil result
            assert !result[1].start_with?('Finished Normally'), 'Job Finished normally. Sleep not long enough?'
            assert result[1].start_with? 'Caught SignalException', 'Signal exception not raised in child.'

            # ensure that the child pid is no longer running
            child_still_running = !(`ps -p #{child_pid.to_s} -o pid=`).empty?
            assert !child_still_running

            # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
            post_cleanup_occurred = Resque.redis.lpop( 'sigterm-test:final' )
            assert post_cleanup_occurred, 'post cleanup did not occur. SIGKILL sent too early?' if rescue_time.nil?
            assert !post_cleanup_occurred, 'post cleanup occurred. SIGKILL sent too late?' unless rescue_time.nil?

          ensure
            remaining_keys = Resque.redis.keys('sigterm-test:*') || []
            Resque.redis.del(*remaining_keys) unless remaining_keys.empty?
          end
        end
      end
    end

    test "exits with Resque::TermException when using TERM_CHILD and not forking" do
      begin
        class LongRunningJob
          @queue = :long_running_job

          def self.perform(run_time)
            Resque.redis.client.reconnect # get its own connection
            Resque.redis.rpush('term-exception-test:start', Process.pid)
            sleep run_time
            Resque.redis.rpush('term-exception-test:result', 'Finished Normally')
          rescue Resque::TermException => e
            Resque.redis.rpush('term-exception-test:result', %Q(Caught TermException: #{e.inspect}))
          ensure
            Resque.redis.rpush('term-exception-test:final', 'exiting.')
          end
        end

        Resque.enqueue(LongRunningJob, 5)

        worker_pid = Kernel.fork do
          # reconnect to redis
          Resque.redis.client.reconnect

          # ensure we don't fork (in worker)
          $TESTING = false
          ENV['FORK_PER_JOB'] = 'false'

          worker = Resque::Worker.new(:long_running_job)
          worker.term_timeout = 1
          worker.term_child = 1

          worker.work(0)
          exit!
        end

        # ensure the worker is started
        start_status = Resque.redis.blpop('term-exception-test:start', 5)
        assert_not_nil start_status
        child_pid = start_status[1].to_i
        assert_operator child_pid, :>, 0

        # send signal to abort the worker
        Process.kill('TERM', worker_pid)
        Process.waitpid(worker_pid)

        # wait to see how it all came down
        result = Resque.redis.blpop('term-exception-test:result', 5)
        assert_not_nil result
        assert !result[1].start_with?('Finished Normally'), 'Job finished normally. Sleep not long enough?'
        assert result[1].start_with?('Caught TermException'), 'TermException not raised in child.'

        # ensure that the child pid is no longer running
        child_still_running = !(`ps -p #{child_pid.to_s} -o pid=`).empty?
        assert !child_still_running

        # see if post-cleanup occurred.
        post_cleanup_occurred = Resque.redis.lpop( 'term-exception-test:final' )
        assert post_cleanup_occurred, 'post cleanup did not occur. SIGKILL sent too early?'

      ensure
        remaining_keys = Resque.redis.keys('term-exception-test:*') || []
        Resque.redis.del(*remaining_keys) unless remaining_keys.empty?
      end
    end

    test "displays warning when not using term_child" do
      begin
        $TESTING = false
        stdout, stderr = capture_io { @worker.work(0) }

        assert stderr.match(/^WARNING:/)
      ensure
        $TESTING = true
      end
    end

    test "it does not display warning when using term_child" do
      @worker.term_child = "1"
      stdout, stderr = capture_io { @worker.work(0) }

      assert !stderr.match(/^WARNING:/)
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

    test "will notify failure hooks when a job is killed by a signal" do
      begin
        $TESTING = false
        Resque.enqueue(SuicidalJob)
        suppress_warnings do
          @worker.work(0)
        end
        assert_equal Resque::DirtyExit, SuicidalJob.send(:class_variable_get, :@@failure_exception).class
      ensure
        $TESTING = true
      end
    end
  end

  test "displays warning when using verbose" do
    begin
      $TESTING = false
      stdout, stderr = capture_io { @worker.verbose }
    ensure
      $TESTING = true
    end
    $warned_logger_severity_deprecation = false

    assert stderr.match(/WARNING:/)
  end

  test "displays warning when using verbose=" do
    begin
      $TESTING = false
      stdout, stderr = capture_io { @worker.verbose = true }
    ensure
      $TESTING = true
    end
    $warned_logger_severity_deprecation = false

    assert stderr.match(/WARNING:/)
  end

  test "displays warning when using very_verbose" do
    begin
      $TESTING = false
      stdout, stderr = capture_io { @worker.very_verbose }
    ensure
      $TESTING = true
    end
    $warned_logger_severity_deprecation = false

    assert stderr.match(/WARNING:/)
  end

  test "displays warning when using very_verbose=" do
    begin
      $TESTING = false
      stdout, stderr = capture_io { @worker.very_verbose = true }
    ensure
      $TESTING = true
    end
    $warned_logger_severity_deprecation = false

    assert stderr.match(/WARNING:/)
  end
end
