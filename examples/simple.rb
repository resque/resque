# This is a simple Resque job.
class Archive
  @queue = :file_serve

  def self.perform(repo_id, branch = 'master')
    repo = Repository.find(repo_id)
    repo.create_archive(branch)
  end
end

# This is in our app code
class Repository < Model
  # ... stuff ...

  def async_create_archive(branch)
    Resque.enqueue(Archive, self.id, branch)
  end

  # ... more stuff ...
end

# Calling this code:
repo = Repository.find(22)
repo.async_create_archive('homebrew')

# Will return immediately and create a Resque job which is later
# processed.

# Essentially, this code is run by the worker when processing:
Archive.perform(22, 'homebrew')
