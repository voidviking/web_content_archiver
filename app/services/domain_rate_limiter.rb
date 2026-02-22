# frozen_string_literal: true

# Enforces a maximum number of concurrent in-flight requests per domain.
#
# Each domain gets its own condition variable so that releasing one domain's
# slot never causes threads waiting on a different domain to spin unnecessarily.
#
# Usage:
#   limiter = DomainRateLimiter.new(max_concurrency: 5)
#   limiter.acquire("cdn.example.com")
#   # ... perform request ...
#   limiter.release("cdn.example.com")
#
#   # Or with a block (preferred — release is guaranteed):
#   limiter.with_domain("cdn.example.com") { ResourceFetcher.call(url) }
class DomainRateLimiter
  DEFAULT_MAX_CONCURRENCY = 5

  def initialize(max_concurrency: DEFAULT_MAX_CONCURRENCY)
    @max_concurrency = max_concurrency
    @registry_mutex  = Mutex.new        # guards reads/writes to @domains hash
    @domains         = {}               # domain => { count: Integer, cond: ConditionVariable }
  end

  # Blocks the calling thread until a slot is available for +domain+,
  # then increments the in-flight counter.
  #
  # @param domain [String] e.g. "cdn.example.com"
  def acquire(domain)
    mutex, cond = entry_for(domain)

    mutex.synchronize do
      cond.wait(mutex) while @domains[domain][:count] >= @max_concurrency
      @domains[domain][:count] += 1
    end
  end

  # Decrements the in-flight counter for +domain+ and wakes one waiting thread.
  # Must be called after every +acquire+, ideally inside an +ensure+ block.
  #
  # @param domain [String]
  def release(domain)
    mutex, cond = entry_for(domain)

    mutex.synchronize do
      @domains[domain][:count] -= 1
      cond.signal
    end
  end

  # Acquires a slot, yields, then releases in an +ensure+ block.
  #
  # @param domain [String]
  # @yieldreturn [Object] value returned from the block
  def with_domain(domain)
    acquire(domain)
    yield
  ensure
    release(domain)
  end

  # Current in-flight count for a domain (useful for testing/observability).
  #
  # @param domain [String]
  # @return [Integer]
  def count(domain)
    return 0 unless @domains.key?(domain)

    @domains[domain][:count]
  end

  private

  # Returns (or lazily creates) the [mutex, cond_var] pair for a domain.
  # The registry mutex ensures two threads don't race on creating the same entry.
  def entry_for(domain)
    @registry_mutex.synchronize do
      @domains[domain] ||= { count: 0, mutex: Mutex.new, cond: ConditionVariable.new }
    end

    entry = @domains[domain]
    [ entry[:mutex], entry[:cond] ]
  end
end
