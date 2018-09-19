require 'test_helper'

describe "Resque::WorkerManager" do
  it "prunes dead workers with heartbeat older than prune interval" do
    assert_equal({}, Resque::WorkerManager.all_heartbeats)
    now = Time.now

    workerA = Resque::Worker.new(:jobs)
    workerA.to_s = "bar:3:jobs"
    workerA.register_worker
    workerA.heartbeat!(now - Resque.prune_interval - 1)

    assert_equal 1, Resque.workers.size
    assert Resque::WorkerManager.all_heartbeats.key?(workerA.to_s)

    workerB = Resque::Worker.new(:jobs)
    workerB.to_s = "foo:5:jobs"
    workerB.register_worker
    workerB.heartbeat!(now)

    assert_equal 2, Resque.workers.size
    assert Resque::WorkerManager.all_heartbeats.key?(workerB.to_s)
    assert_equal [workerA], Resque::WorkerManager.all_workers_with_expired_heartbeats

    Resque::WorkerManager.prune_dead_workers

    assert_equal 1, Resque.workers.size
    refute Resque::WorkerManager.all_heartbeats.key?(workerA.to_s)
    assert Resque::WorkerManager.all_heartbeats.key?(workerB.to_s)
    assert_equal [], Resque::WorkerManager.all_workers_with_expired_heartbeats
  end

  it "does not prune if another worker has pruned (started pruning) recently" do
    now = Time.now
    workerA = Resque::Worker.new(:jobs)
    workerA.to_s = 'workerA:1:jobs'
    workerA.register_worker
    workerA.heartbeat!(now - Resque.prune_interval - 1)
    assert_equal 1, Resque.workers.size
    assert_equal [workerA], Resque::WorkerManager.all_workers_with_expired_heartbeats

    workerB = Resque::Worker.new(:jobs)
    workerB.to_s = 'workerB:1:jobs'
    workerB.register_worker
    workerB.heartbeat!(now)
    assert_equal 2, Resque.workers.size

    Resque::WorkerManager.prune_dead_workers
    assert_equal [], Resque::WorkerManager.all_workers_with_expired_heartbeats

    workerC = Resque::Worker.new(:jobs)
    workerC.to_s = "workerC:1:jobs"
    workerC.register_worker
    workerC.heartbeat!(now - Resque.prune_interval - 1)
    assert_equal 2, Resque.workers.size
    assert_equal [workerC], Resque::WorkerManager.all_workers_with_expired_heartbeats

    workerD = Resque::Worker.new(:jobs)
    workerD.to_s = 'workerD:1:jobs'
    workerD.register_worker
    workerD.heartbeat!(now)
    assert_equal 3, Resque.workers.size

    # workerC does not get pruned because workerB already pruned recently
    Resque::WorkerManager.prune_dead_workers
    assert_equal [workerC], Resque::WorkerManager.all_workers_with_expired_heartbeats
  end

  it "does not prune workers that haven't set a heartbeat" do
    workerA = Resque::Worker.new(:jobs)
    workerA.to_s = "bar:3:jobs"
    workerA.register_worker

    assert_equal 1, Resque.workers.size
    assert_equal({}, Resque::WorkerManager.all_heartbeats)

    Resque::WorkerManager.prune_dead_workers

    assert_equal 1, Resque.workers.size
  end

  it "does return a valid time when asking for heartbeat" do
    workerA = Resque::Worker.new(:jobs)
    workerA.register_worker
    workerA.heartbeat!

    assert_instance_of Time, workerA.heartbeat

    workerA.remove_heartbeat
    assert_equal nil, workerA.heartbeat
  end

  it "removes old heartbeats before starting heartbeat thread" do
    workerA = Resque::Worker.new(:jobs)
    workerA.register_worker
    workerA.expects(:remove_heartbeat).once
    workerA.start_heartbeat
  end

  it "cleans up heartbeat after unregistering" do
    workerA = Resque::Worker.new(:jobs)
    workerA.register_worker
    workerA.start_heartbeat

    Timeout.timeout(5) do
      sleep 0.1 while Resque::WorkerManager.all_heartbeats.empty?

      assert Resque::WorkerManager.all_heartbeats.key?(workerA.to_s)
      assert_instance_of Time, workerA.heartbeat

      workerA.unregister_worker
      sleep 0.1 until Resque::WorkerManager.all_heartbeats.empty?
    end

    assert_equal nil, workerA.heartbeat
  end

  it "does not generate heartbeats that depend on the worker clock, but only on the server clock" do
    server_time_before = Resque.data_store.server_time
    fake_time = Time.parse("2000-01-01")

    with_fake_time(fake_time) do
      worker_time = Time.now

      workerA = Resque::Worker.new(:jobs)
      workerA.register_worker
      workerA.heartbeat!

      heartbeat_time = workerA.heartbeat
      refute_equal heartbeat_time, worker_time

      server_time_after = Resque.data_store.server_time
      assert server_time_before <= heartbeat_time
      assert heartbeat_time <= server_time_after
    end
  end

  it "correctly reports errors that occur while pruning workers" do
    workerA = Resque::Worker.new(:jobs)
    workerA.to_s = "bar:3:jobs"
    workerA.register_worker
    workerA.heartbeat!(Time.now - Resque.prune_interval - 1)

    Resque::WorkerManager.stubs(:data_store).raises(Redis::CannotConnectError)

    exception_caught = assert_raises Redis::CannotConnectError do
      Resque::WorkerManager.prune_dead_workers
    end

    assert_match(/Redis::CannotConnectError/, exception_caught.message)
  end
end
