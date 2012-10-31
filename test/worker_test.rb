require 'test_helper'

describe "Resque::Worker" do
  before do
    Resque.redis = Resque.redis # reset state in Resque object
    Resque.redis.flushall

    Resque.before_first_fork = nil
    Resque.before_fork = nil
    Resque.after_fork = nil

    @worker = Resque::Worker.new(:jobs)
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
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

  it "unavailable job definition reports exception and message" do
    Resque::Job.create(:jobs, 'NoJobDefinition')
    @worker.work(0)
    assert_equal 1, Resque::Failure.count, 'failure not reported'
    assert_equal('NameError', Resque::Failure.all['exception'])
    assert_match('uninitialized constant', Resque::Failure.all['error'])
  end

  it "validates jobs before enquing them." do
    assert_raises Resque::NoQueueError do
      Resque.enqueue(JobWithNoQueue)
    end
  end

  it "does not allow exceptions from failure backend to escape" do
    job = Resque::Job.new(:jobs, {})
    with_failure_backend BadFailureBackend do
      @worker.perform job
    end
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

  it "can work on all queues" do
    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    worker = Resque::Worker.new("*")

    worker.work(0)
    assert_equal 0, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)
    assert_equal 0, Resque.size(:blahblah)
  end

  it "can work with wildcard at the end of the list" do
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

  it "can work with wildcard at the middle of the list" do
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

  it "preserves order with a wildcard in the middle of a list" do
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:bulk, GoodJob)

    worker = Resque::Worker.new(:beer, "*", :bulk)

    assert_equal %w( beer critical jobs bulk ), worker.queues
  end

  it "processes * queues in alphabetical order" do
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

  it "can work with dynamically added queues when using wildcard" do
    worker = Resque::Worker.new("*")

    assert_equal ["jobs"], Resque.queues

    Resque::Job.create(:high, GoodJob)
    Resque::Job.create(:critical, GoodJob)
    Resque::Job.create(:blahblah, GoodJob)

    processed_queues = []

    worker.work(0) do |job|
      processed_queues << job.queue
    end

    assert_equal %w( jobs high critical blahblah ).sort, processed_queues
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
    worker = Resque::Worker.new(:perform_less)
    Resque::Job.create(:perform_less, Object)

    assert_equal 0, Resque::Failure.count
    worker.work(0)
    assert_equal 1, Resque::Failure.count
  end

  it "inserts itself into the 'workers' list on startup" do
    @worker.work(0) do
      assert_equal @worker, Resque.workers[0]
    end
  end

  it "removes itself from the 'workers' list on shutdown" do
    @worker.work(0) do
      assert_equal @worker, Resque.workers[0]
    end

    assert_equal [], Resque.workers
  end

  it "removes worker with stringified id" do
    @worker.work(0) do
      worker_id = Resque.workers[0].to_s
      Resque.remove_worker(worker_id)
      assert_equal [], Resque.workers
    end
  end

  it "records what it is working on" do
    @worker.work(0) do
      task = @worker.job
      assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
      assert task['run_at']
      assert_equal 'jobs', task['queue']
    end
  end

  it "clears its status when not working on anything" do
    @worker.work(0)
    assert_equal Hash.new, @worker.job
  end

  it "knows when it is working" do
    @worker.work(0) do
      assert @worker.working?
    end
  end

  it "knows when it is idle" do
    @worker.work(0)
    assert @worker.idle?
  end

  it "knows who is working" do
    @worker.work(0) do
      assert_equal [@worker], Resque.working
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

  it "reserve blocks when the queue is empty" do
    worker = Resque::Worker.new(:timeout)

    assert_raises Timeout::Error do
      Timeout.timeout(1) { worker.reserve(5) }
    end
  end

  it "reserve returns nil when there is no job and is polling" do
    worker = Resque::Worker.new(:timeout)

    assert_equal nil, worker.reserve(1)
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
    @worker.work(0) do
      assert Time.parse(@worker.started) - time < 0.1
    end
  end

  it "knows whether it exists or not" do
    @worker.work(0) do
      assert Resque::Worker.exists?(@worker)
      assert !Resque::Worker.exists?('blah-blah')
    end
  end

  it "sets $0 while working" do
    @worker.work(0) do
      ver = Resque::Version
      assert_equal "resque-#{ver}: Processing jobs since #{Time.now.to_i}", $0
    end
  end

  it "can be found" do
    @worker.work(0) do
      found = Resque::Worker.find(@worker.to_s)
      assert_equal @worker.to_s, found.to_s
      assert found.working?
      assert_equal @worker.job, found.job
    end
  end

  it "doesn't find fakes" do
    @worker.work(0) do
      found = Resque::Worker.find('blah-blah')
      assert_equal nil, found
    end
  end
  
  it "cleans up dead worker info on start (crash recovery)" do
    # first we fake out two dead workers
    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "#{`hostname`.chomp}:1:jobs")
    workerA.register_worker

    workerB = Resque::Worker.new(:high, :low)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}:2:high,low")
    workerB.register_worker

    assert_equal 2, Resque.workers.size

    # then we prune them
    @worker.work(0) do
      assert_equal 1, Resque.workers.size
    end
  end

  it "worker_pids returns pids" do
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

    # TODO: Verify it's only run once. Not easy.
#     workerA.work(0)
#     assert_equal 1, $BEFORE_FORK_CALLED
  end

  it "Passes the worker to the before_first_fork hook" do
    $BEFORE_FORK_WORKER = nil
    Resque.before_first_fork = Proc.new { |w| $BEFORE_FORK_WORKER = w.id }
    workerA = Resque::Worker.new(:jobs)

    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert_equal workerA.id, $BEFORE_FORK_WORKER
  end

  it "Will call a before_fork hook before forking" do
    $BEFORE_FORK_CALLED = false
    Resque.before_fork = Proc.new { $BEFORE_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$BEFORE_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert $BEFORE_FORK_CALLED == workerA.will_fork?
  end
  
  it "Will not call a before_fork hook when the worker can't fork" do
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

  it "Will call an after_fork hook after forking" do
    Resque.redis.flushall
    $AFTER_FORK_CALLED = false
    Resque.after_fork = Proc.new { $AFTER_FORK_CALLED = true }
    workerA = Resque::Worker.new(:jobs)

    assert !$AFTER_FORK_CALLED
    Resque::Job.create(:jobs, SomeJob, 20, '/tmp')
    workerA.work(0)
    assert $AFTER_FORK_CALLED == workerA.will_fork?
  end

  it "Will not call an after_fork hook when the worker can't fork" do
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

  it "reconnects to redis after fork" do
    original_connection = Resque.redis.client.connection.instance_variable_get("@sock")
    @worker.work(0)
    refute_equal original_connection, Resque.redis.client.connection.instance_variable_get("@sock")
  end

  it "tries to reconnect three times before giving up" do
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

  it "will call before_pause before it is paused" do
    before_pause_called = false
    captured_worker = nil

    Resque.before_pause do |worker|
      before_pause_called = true
      captured_worker = worker
    end

    @worker.pause_processing

    assert !before_pause_called

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert before_pause_called
    assert_equal @worker, captured_worker
  end

  it "will call after_pause after it is paused" do
    after_pause_called = false
    captured_worker = nil

    Resque.after_pause do |worker|
      after_pause_called = true
      captured_worker = worker
    end

    @worker.pause_processing

    assert !after_pause_called

    t = Thread.start { sleep(0.1); Process.kill('CONT', @worker.pid) }

    @worker.work(0)

    t.join

    assert after_pause_called
    assert_equal @worker, captured_worker
  end

  if !defined?(RUBY_ENGINE) || defined?(RUBY_ENGINE) && RUBY_ENGINE != "jruby"
    [SignalException, Resque::TermException].each do |exception|
      {
        'cleanup occurs in allotted time' => nil,
        'cleanup takes too long' => 2
      }.each do |scenario,rescue_time|
        it "SIGTERM when #{scenario} while catching #{exception}" do
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

              worker.work(0)
              exit!
            end

            # ensure the worker is started
            start_status = Resque.redis.blpop( 'sigterm-test:start', 5 )
            refute_nil start_status
            child_pid = start_status[1].to_i
            assert_operator child_pid, :>, 0

            # send signal to abort the worker
            Process.kill('TERM', worker_pid)
            Process.waitpid(worker_pid)

            # wait to see how it all came down
            result = Resque.redis.blpop( 'sigterm-test:result', 5 )
            refute_nil result
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
      begin
        $TESTING = false
        Resque.enqueue(SuicidalJob)
        @worker.work(0)
        assert_equal Resque::DirtyExit, SuicidalJob.send(:class_variable_get, :@@failure_exception).class
      ensure
        $TESTING = true
      end
    end
  end
  
  it "constantizes" do
    assert_same Kernel, Resque::Worker.constantize(:Kernel)
    assert_same MiniTest::Unit::TestCase, Resque::Worker.constantize('MiniTest::Unit::TestCase')
    assert_raises NameError do
      Resque::Worker.constantize('Object::MissingConstant')
    end
  end
  
end
