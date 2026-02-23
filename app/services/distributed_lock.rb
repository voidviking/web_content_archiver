# frozen_string_literal: true

# Distributed lock backed by Redis using the Redlock algorithm.
#
# Guarantees that only one process at a time can execute a critical section
# across multiple application servers / Sidekiq workers.
#
# Usage:
#   result = DistributedLock.acquire("archive:#{url}") { do_work }
#   # result is nil  → lock was held by another process; block did NOT run
#   # result is truthy → block ran and returned that value
#
# The lock is always released in an ensure block, so it is safe to use with
# early returns or exceptions inside the block.
class DistributedLock
  DEFAULT_TTL_MS = 30_000 # 30 seconds

  def self.acquire(key, ttl: DEFAULT_TTL_MS, &block)
    new(key, ttl: ttl).acquire(&block)
  end

  def initialize(key, ttl: DEFAULT_TTL_MS)
    @key = "lock:#{key}"
    @ttl = ttl
  end

  # Tries to acquire the lock.
  #
  # @yieldreturn [Object] the block's return value on success
  # @return [Object, nil] block value if lock was acquired, nil otherwise
  def acquire
    lock_info = lock_manager.lock(@key, @ttl)
    return nil unless lock_info

    yield
  ensure
    lock_manager.unlock(lock_info) if lock_info
  end

  private

  def lock_manager
    @lock_manager ||= Redlock::Client.new([ redis_url ])
  end

  def redis_url
    ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
  end
end
