# DelayedJob wants you to create instances. No problem.

class Archive < Struct.new(:repo_id, :branch)
  def self.perform(*args)
    new(*args).perform
  end

  def perform
    # do work!
  end
end
