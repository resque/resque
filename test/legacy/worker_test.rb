require 'test_helper'
require 'tmpdir'
require 'tempfile'

describe "Resque::Worker" do
  let(:test_options){ { :interval => 0, :timeout => 0 } }
  let(:worker) { Resque::Worker.new(:jobs, test_options) }

  before :each do
    Resque.redis = Resque.backend.store
    Resque.backend.store.flushall

    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil

    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    Resque::Worker.__send__(:public, :pause_processing)
    Resque::Options.__send__(:public, :fork_per_job)
    Resque::Worker.__send__(:public, :reserve)
  end

  it "can fail jobs" do
    # This test forks, so we will use the real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      Resque::Job.create(:jobs, BadJob)
      worker.work
      assert_equal 1, Resque::Failure.count
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "failed jobs report exception and message" do
    # we fork, so let's use real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      Resque::Job.create(:jobs, BadJobWithSyntaxError)
      worker.work
      assert_equal 1, Resque::Failure.count
      assert_equal('SyntaxError', Resque::Failure.all.first['exception'])
      assert_equal('Extra Bad job!', Resque::Failure.all.first['error'])
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "unavailable job definition reports exception and message" do
    Resque::Job.create(:jobs, 'NoJobDefinition')
    stub_to_fork(worker, false) do
      worker.work
      assert_equal 1, Resque::Failure.count, 'failure not reported'
      assert_equal('NameError', Resque::Failure.all.first['exception'])
      assert_match('uninitialized constant', Resque::Failure.all.first['error'])
    end
  end

  it "validates jobs before enquing them." do
    assert_raises Resque::NoQueueError do
      Resque.enqueue(JobWithNoQueue)
    end
  end

  it "does not allow exceptions from failure backend to escape" do
    job = Resque::Job.new(:jobs, {})
    with_failure_backend BadFailureBackend do
      worker.perform job
    end
  end

  it "does report failure for jobs with invalid payload" do
    job = Resque::Job.new(:jobs, { 'class' => 'NotAValidJobClass', 'args' => '' })
    worker.perform job
    assert_equal 1, Resque::Failure.count, 'failure not reported'
  end

  it "register 'run_at' time on UTC timezone in ISO8601 format" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    now = Time.now.utc.iso8601
    registry = Resque::WorkerRegistry.new(worker)
    registry.working_on worker, job
    assert_equal now, registry.processing['run_at']
  end

  it "defines the jruby? method" do
    worker.send(:jruby?) #doesn't raise exception
  end

  unless jruby?

    it "does not raise exception for completed jobs" do
      if worker_pid = Kernel.fork
        Process.waitpid(worker_pid)
        assert_equal 0, Resque::Failure.count
      else
        Resque.backend.store.client.reconnect
        worker = Resque::Worker.new(:jobs, test_options)
        worker.work
        exit
      end
    end

    it "executes at_exit hooks on exit" do
      tmpfile = File.join(Dir.tmpdir, "resque_at_exit_test_file")
      FileUtils.rm_f tmpfile

      if worker_pid = Kernel.fork
        Process.waitpid(worker_pid)
        assert File.exist?(tmpfile), "The file '#{tmpfile}' does not exist"
        assert_equal "at_exit", File.open(tmpfile).read.strip
      else
        Resque.backend.store.client.reconnect
        Resque::Job.create(:at_exit_jobs, AtExitJob, tmpfile)
        worker = Resque::Worker.new(:at_exit_jobs, test_options.merge(:run_at_exit_hooks => true))
        worker.work
        exit
      end

    end
  end

  it "fails uncompleted jobs with DirtyExit by default on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    registry = Resque::WorkerRegistry.new(worker)
    registry.working_on(worker, job)
    registry.unregister
    assert_equal 1, Resque::Failure.count
    assert_equal('Resque::DirtyExit', Resque::Failure.all.first['exception'])
  end

  it "fails uncompleted jobs with worker exception on exit" do
    job = Resque::Job.new(:jobs, {'class' => 'GoodJob', 'args' => "blah"})
    registry = Resque::WorkerRegistry.new(worker)
    registry.working_on worker, job
    registry.unregister(StandardError.new)
    assert_equal 1, Resque::Failure.count
    assert_equal('StandardError', Resque::Failure.all.first['exception'])
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
    registry = Resque::WorkerRegistry.new(worker)
    registry.working_on worker, job
    registry.unregister
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

  it "only calls failure hook once on exception" do
    job = Resque::Job.new(:jobs, {'class' => 'SimpleFailingJob', 'args' => ""})
    worker.perform(job)
    assert_equal 1, Resque::Failure.count
    assert_equal 1, SimpleFailingJob.exception_count
  end

  it "can peek at failed jobs" do
    # This test forks so we'll use the real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      10.times { Resque::Job.create(:jobs, BadJob) }
      worker.work
      assert_equal 10, Resque::Failure.count

      assert_equal 10, Resque::Failure.all(0, 20).size
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "can clear failed jobs" do
    # This test forks so we'll use the real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      Resque::Job.create(:jobs, BadJob)
      worker.work
      assert_equal 1, Resque::Failure.count
      Resque::Failure.clear
      assert_equal 0, Resque::Failure.count
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "catches exceptional jobs" do
    # This test forks so we'll use the real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      Resque::Job.create(:jobs, BadJob)
      Resque::Job.create(:jobs, BadJob)
      worker.process
      worker.process
      worker.process
      assert_equal 2, Resque::Failure.count
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "strips whitespace from queue names" do
    queues = "critical, high, low".split(',')
    worker = Resque::Worker.new(queues)
    assert_equal %w( critical high low ), worker.queues
  end

  it "can work on multiple queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)

    worker = Resque::Worker.new([:critical, :high], test_options)

    worker.process
    assert_equal 1, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)

    worker.process
    assert_equal 0, Resque.size(:high)
  end

  it "can work on all queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    worker = Resque::Worker.new("*", test_options)

    worker.work
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
  end

  it "can work with wildcard at the end of the list" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)
    Resque::Job.create(:beer, GoodJob)

    worker = Resque::Worker.new([:critical, :high, "*"], test_options)

    worker.work
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

    worker = Resque::Worker.new([:critical, "*", :high], test_options)

    worker.work
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
    assert_equal 0, Resque.size(:beer)
  end

  it "preserves order with a wildcard in the middle of a list" do
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:bulk, GoodJob)

    worker = Resque::Worker.new([:beer, "*", :bulk])

    assert_equal %w( beer critical jobs bulk ), worker.queues
  end

  it "processes * queues in alphabetical order" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)


    worker = Resque::Worker.new("*", test_options)
    stub_to_fork(worker, false) do
      processed_queues = []

      worker.work do |job|
        processed_queues << job.queue
      end

      assert_equal %w( jobs high critical blahblah ).sort, processed_queues
    end
  end

  it "can work with dynamically added queues when using wildcard" do
    worker = Resque::Worker.new("*", test_options)
    stub_to_fork(worker, false) do

      assert_equal ["jobs"], Resque.queues

      Resque::Job.create(:high, GoodJob)
      Resque::Job.create(:critical, GoodJob)
      Resque::Job.create(:blahblah, GoodJob)

      processed_queues = []

      worker.work do |job|
        processed_queues << job.queue
      end

      assert_equal %w( jobs high critical blahblah ).sort, processed_queues
    end
  end

  it "has a unique id" do
    assert_equal "#{`hostname`.chomp}:#{$$}:jobs", worker.to_s
  end

  it "complains if no queues are given" do
    assert_raises Resque::NoQueueError do
      Resque::Worker.new
    end
  end

  it "fails if a job class has no `perform` method" do
    # This test forks so let's use real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      worker = Resque::Worker.new(:perform_less, test_options)
      Resque::Job.create(:perform_less, Object)

      assert_equal 0, Resque::Failure.count
      worker.work
      assert_equal 1, Resque::Failure.count
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "inserts itself into the 'workers' list on startup" do
    worker.work do
      assert_equal worker, Resque::WorkerRegistry.all[0]
    end
  end

  it "removes itself from the 'workers' list on shutdown" do
    worker.work do
      assert_equal worker, Resque::WorkerRegistry.all[0]
    end

    assert_equal [], Resque::WorkerRegistry.all
  end

  it "removes worker with stringified id" do
    worker.work do
      worker_id = Resque::WorkerRegistry.all[0].to_s
      Resque::WorkerRegistry.remove(worker_id)
      assert_equal [], Resque::WorkerRegistry.all
    end
  end

  it "records what it is working on" do
    worker.work do
      registry = Resque::WorkerRegistry.new(worker)
      task = registry.job
      assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
      assert task['run_at']
      assert_equal 'jobs', task['queue']
    end
  end

  it "clears its status when not working on anything" do
    worker.work
    registry = Resque::WorkerRegistry.new(worker)
    assert_equal Hash.new, registry.job
  end

  it "knows when it is working" do
    worker.work do
      assert worker.working?
    end
  end

  it "knows when it is idle" do
    worker.work
    assert worker.idle?
  end

  it "knows who is working" do
    worker.work do
      assert_equal [worker], Resque::WorkerRegistry.working
    end
  end

  it "keeps track of how many jobs it has processed" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = worker.reserve
      worker.process job
    end
    assert_equal 3, worker.processed
  end

  it "reserve blocks when the queue is empty" do
    # due to difference in behavior regarding timeouts, let's
    # use real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      worker = Resque::Worker.new(:timeout, test_options)

      # In MockRedis, this will return nil rather than throwing
      # the timeout error.
      assert_raises Timeout::Error do
        Timeout.timeout(1) { worker.reserve(5) }
      end
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "reserve returns nil when there is no job and is polling" do
    worker = Resque::Worker.new(:timeout, test_options)

    assert_equal nil, worker.reserve(1)
  end

  it "keeps track of how many failures it has seen" do
    Resque::Job.create(:jobs, BadJob)
    Resque::Job.create(:jobs, BadJob)

    3.times do
      job = worker.reserve
      worker.process job
    end
    assert_equal 2, worker.failed
  end

  it "stats are erased when the worker goes away" do
    worker.work
    assert_equal 0, worker.processed
    assert_equal 0, worker.failed
  end

  it "knows when it started" do
    time = Time.now
    worker.work do
      registry = Resque::WorkerRegistry.new(worker)
      assert Time.parse(registry.started) - time < 0.1
    end
  end

  it "knows whether it exists or not" do
    worker.work do
      assert Resque::WorkerRegistry.exists?(worker)
      assert !Resque::WorkerRegistry.exists?('blah-blah')
    end
  end

  it "sets $0 while working" do
    stub_to_fork(worker, false) do
      worker.work do
        prefix = ENV['RESQUE_PROCLINE_PREFIX']
        ver = Resque::Version
        assert_equal "#{prefix}resque-#{ver}: Processing jobs since #{Time.now.iso8601} [SomeJob]", $0
      end
    end
  end

  it "can be found" do
    worker.work do
      found = Resque::WorkerRegistry.find(worker.to_s)
      assert_equal worker.to_s, found.to_s
      assert found.working?
      registry = Resque::WorkerRegistry.new(worker)
      assert_equal registry.job, Resque::WorkerRegistry.new(found).job
    end
  end

  it "doesn't find fakes" do
    worker.work do
      found = Resque::WorkerRegistry.find('blah-blah')
      assert_equal nil, found
    end
  end

  it "cleans up dead worker info on start (crash recovery)" do
    # first we fake out two dead workers
    workerA = Resque::Worker.new(:jobs, test_options)
    workerA.instance_variable_set(:@to_s, "#{`hostname`.chomp}:1:jobs")
    registry = Resque::WorkerRegistry.new(workerA)
    registry.register

    workerB = Resque::Worker.new([:high, :low], test_options)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}:2:high,low")
    registry = Resque::WorkerRegistry.new(workerB)
    registry.register

    assert_equal 2, Resque::WorkerRegistry.all.size

    # then we prune them
    worker.work do
      # noop
    end
    assert_equal 1, Resque::WorkerRegistry.all.size
  end

  it "worker_pids returns pids" do
    known_workers = Resque::ProcessCoordinator.new.worker_pids
    assert !known_workers.empty?
  end

  it "Processed jobs count" do
    worker.work
    assert_equal 1, Resque.info[:processed]
  end

  it "Will call a before_first_fork hook only once" do
    $BEFORE_FORK_CALLED = 0
    Resque.before_first_fork = Proc.new { $BEFORE_FORK_CALLED += 1 }
    workerA = Resque::Worker.new(:jobs, test_options)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')

    assert_equal 0, $BEFORE_FORK_CALLED

    workerA.work
    assert_equal 1, $BEFORE_FORK_CALLED

    # TODO: Verify it's only run once. Not easy.
#     workerA.work
#     assert_equal 1, $BEFORE_FORK_CALLED
  end

  it "Passes the worker to the before_first_fork hook" do
    $BEFORE_FORK_WORKER = nil
    Resque.before_first_fork = Proc.new { |w| $BEFORE_FORK_WORKER = w.id }
    workerA = Resque::Worker.new(:jobs, test_options)

    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work
    assert_equal workerA.id, $BEFORE_FORK_WORKER
  end

  it "Will call a before_fork hook before forking" do
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs, test_options)

    assert !$BEFORE_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work
    #Was: assert $BEFORE_FORK_CALLED == workerA.will_fork?
    #TODO: was this test implying we shouldn't call this hook if we don't plan to fork (because legacy behavior is that we do...)
    assert($BEFORE_FORK_CALLED)
  end

  it "Will not call a before_fork hook when the worker can't fork" do
    Resque.backend.store.flushall
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs, test_options.merge(:fork_per_job => false))

    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called before job runs"
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work
    assert !$BEFORE_FORK_CALLED, "before_fork should not have been called after job runs"
  end

  it "Will call an after_fork hook after forking" do
    # we fork, therefore, real redis
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      msg = "called!"
      Resque.after_fork = Proc.new { Resque.backend.store.set("after_fork", msg) }
      workerA = Resque::Worker.new(:jobs, test_options)

      Resque::Job.create(:jobs, SomeJob, 20, '/tmp')

      workerA.work
      val = Resque.backend.store.get("after_fork")
      assert_equal val, msg
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "Will not call an after_fork hook when the worker can't fork" do
    Resque.backend.store.flushall
    $AFTER_FORK_CALLED = false
    Resque.after_fork = Proc.new { Resque.backend.store.set("after_fork", "yeah") }
    workerA = Resque::Worker.new(:jobs, test_options.merge(:fork_per_job => false))

    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work
    assert_nil Resque.backend.store.get("after_fork")
  end

  it "returns PID of running process" do
    assert_equal worker.to_s.split(":")[1].to_i, worker.pid
  end

  it "requeue failed queue" do
    queue = 'good_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue, test_options), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue, test_options), :queue => 'some_job', :payload => {'class' => 'SomeJob'})
    Resque::Failure.requeue_queue(queue)
    assert Resque::Failure.all(0).first.has_key?('retried_at')
    assert !Resque::Failure.all(1).first.has_key?('retried_at')
  end

  it "remove failed queue" do
    queue = 'good_job'
    queue2 = 'some_job'
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue, test_options), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue2, test_options), :queue => queue2, :payload => {'class' => 'SomeJob'})
    Resque::Failure.create(:exception => Exception.new, :worker => Resque::Worker.new(queue, test_options), :queue => queue, :payload => {'class' => 'GoodJob'})
    Resque::Failure.remove_queue(queue)
    assert_equal queue2, Resque::Failure.all(0).first['queue']
    assert_equal 1, Resque::Failure.count
  end

  it "reconnects to redis after fork" do
    skip "JRuby doesn't fork." if jruby?
    file = Tempfile.new("reconnect")
    proc = Proc.new { File.open(file.path, "w+") { |f| f.write("foo")} }
    # Somewhat of a pain to test because the child will fork, so need to communicate across processes and not use
    # Redis (since we're stubbing out reconnect...)
    Resque.backend.store.client.stub(:reconnect, proc) do
      worker.work
      val = File.read(file.path)
      assert_equal val, "foo"
    end
  end

  it "will call before_pause before it is paused" do
    # this test is kinda weird and complex, so let's punt
    # and use real redis to make sure we don't break stuff
    Resque.redis = $real_redis
    Resque.backend.store.flushall

    begin
      before_pause_called = false
      captured_worker = nil

      Resque.before_pause do |worker|
        before_pause_called = true
        captured_worker = worker
      end

      worker.pause_processing

      assert !before_pause_called

      t = Thread.start { sleep(0.1); Process.kill('CONT', worker.pid) }

      worker.work

      t.join

      assert before_pause_called
      assert_equal worker, captured_worker
    ensure
      Resque.redis = $mock_redis
    end
  end

  it "will call after_pause after it is paused" do
    after_pause_called = false
    captured_worker = nil

    Resque.after_pause do |worker|
      after_pause_called = true
      captured_worker = worker
    end

    worker.pause_processing

    assert !after_pause_called

    t = Thread.start { sleep(0.1); Process.kill('CONT', worker.pid) }

    worker.work

    t.join

    assert after_pause_called
    assert_equal worker, captured_worker
  end

  unless jruby?
    [SignalException, Resque::TermException].each do |exception|
      {
        'cleanup occurs in allotted time' => nil,
        'cleanup takes too long' => 2
      }.each do |scenario,rescue_time|
        it "SIGTERM when #{scenario} while catching #{exception}" do
          begin
            Resque.redis = $real_redis
            eval("class LongRunningJob; @@exception = #{exception}; end")
            class LongRunningJob
              @queue = :long_running_job

              #warning: previous definition of perform was here
              silence_warnings do
                def self.perform( run_time, rescue_time=nil )
                  Resque.backend.store.client.reconnect # get its own connection
                  Resque.backend.store.rpush( 'sigterm-test:start', Process.pid )
                  sleep run_time
                  Resque.backend.store.rpush( 'sigterm-test:result', 'Finished Normally' )
                rescue @@exception => e
                  Resque.backend.store.rpush( 'sigterm-test:result', %Q(Caught SignalException: #{e.inspect}))
                  sleep rescue_time unless rescue_time.nil?
                ensure
                  Resque.backend.store.rpush( 'sigterm-test:final', 'exiting.' )
                end
              end
            end

            Resque.enqueue( LongRunningJob, 5, rescue_time )

            worker_pid = Kernel.fork do
              # reconnect since we just forked
              Resque.backend.store.client.reconnect

              worker = Resque::Worker.new(:long_running_job, test_options.merge(:timeout => 1))
              worker.work

              exit!
            end

            # ensure the worker is started
            start_status = Resque.backend.store.blpop( 'sigterm-test:start', 5 )
            refute_nil start_status
            child_pid = start_status[1].to_i
            assert_operator child_pid, :>, 0

            # send signal to abort the worker
            Process.kill('TERM', worker_pid)
            Process.waitpid(worker_pid)

            # wait to see how it all came down
            result = Resque.backend.store.blpop( 'sigterm-test:result', 5 )
            refute_nil result
            assert !result[1].start_with?('Finished Normally'), 'Job Finished normally. Sleep not long enough?'
            assert result[1].start_with? 'Caught SignalException', 'Signal exception not raised in child.'

            # ensure that the child pid is no longer running
            child_not_running = `ps -p #{child_pid.to_s} -o pid=`.empty?
            assert child_not_running

            # see if post-cleanup occurred. This should happen IFF the rescue_time is less than the term_timeout
            post_cleanup_occurred = Resque.backend.store.lpop( 'sigterm-test:final' )
            assert post_cleanup_occurred, 'post cleanup did not occur. SIGKILL sent too early?' if rescue_time.nil?
            assert !post_cleanup_occurred, 'post cleanup occurred. SIGKILL sent too late?' unless rescue_time.nil?

          ensure
            remaining_keys = Resque.backend.store.keys('sigterm-test:*') || []
            Resque.backend.store.del(*remaining_keys) unless remaining_keys.empty?
            Resque.redis = $mock_redis
          end
        end
      end

      it "SIGTERM with graceful_term allows job to complete" do
        begin
          Resque.redis = $real_redis
          class LongRunningJob
            @queue = :long_running_job

            #warning: previous definition of perform was here
            silence_warnings do
              def self.perform( run_time, rescue_time=nil )
                Resque.backend.store.client.reconnect # get its own connection
                Resque.backend.store.rpush( 'sigterm-test:start', Process.pid )
                sleep 0.1
                Resque.backend.store.rpush( 'sigterm-test:result', 'Finished Normally' )
              end
            end
          end

          Resque.enqueue(LongRunningJob, 5)

          worker_pid = Kernel.fork do
            # reconnect since we just forked
            Resque.backend.store.client.reconnect

            worker = Resque::Worker.new(:long_running_job, test_options.merge(:graceful_term => true))
            worker.work

            exit!
          end

          # ensure the worker is started
          start_status = Resque.backend.store.blpop( 'sigterm-test:start', 5 )
          refute_nil start_status
          child_pid = start_status[1].to_i
          assert_operator child_pid, :>, 0

          # send signal to abort the worker
          Process.kill('TERM', worker_pid)
          Process.waitpid(worker_pid)

          # wait to see how it all came down
          result = Resque.backend.store.blpop( 'sigterm-test:result', 5 )
          refute_nil result
          assert result[1].start_with?('Finished Normally')

          # ensure that the child pid is no longer running
          child_not_running = `ps -p #{child_pid.to_s} -o pid=`.empty?
          assert child_not_running

        ensure
          remaining_keys = Resque.backend.store.keys('sigterm-test:*') || []
          Resque.backend.store.del(*remaining_keys) unless remaining_keys.empty?
          Resque.redis = $mock_redis
        end
      end

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
      stub_to_fork(worker, true) do
        Resque.enqueue(SuicidalJob)
        worker.work
        assert_equal Resque::DirtyExit, SuicidalJob.send(:class_variable_get, :@@failure_exception).class
      end
    end
  end
end
