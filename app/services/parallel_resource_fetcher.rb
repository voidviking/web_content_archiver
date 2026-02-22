# frozen_string_literal: true

# Fetches a collection of web resources in parallel using Ruby threads,
# while respecting per-domain concurrency limits via DomainRateLimiter.
#
# Each resource is fetched in its own thread. All threads are joined before
# results are returned, so the caller always receives a complete result set.
# Failed fetches (ResourceFetcher returning nil) are included in results as
# { url:, result: nil } so callers can distinguish missing from un-attempted.
#
# Usage:
#   resources = [{ url: "https://cdn.example.com/a.css", type: :stylesheet }, ...]
#   results   = ParallelResourceFetcher.call(resources)
#   # => [{ url: "https://cdn.example.com/a.css", type: :stylesheet,
#   #        result: { body: "...", content_type: "text/css", size: 1234 } }, ...]
class ParallelResourceFetcher
  # Hard ceiling on simultaneous threads regardless of how many resources exist.
  MAX_THREADS = 20

  def self.call(resources, rate_limiter: nil)
    new(resources, rate_limiter: rate_limiter).call
  end

  # @param resources   [Array<Hash>] each element has :url and :type keys
  # @param rate_limiter [DomainRateLimiter, nil] injected for testability;
  #                     a default instance is created when nil
  def initialize(resources, rate_limiter: nil)
    @resources    = resources
    @rate_limiter = rate_limiter || DomainRateLimiter.new
  end

  # @return [Array<Hash>] array of { url:, type:, result: } hashes
  def call
    return [] if @resources.empty?

    results = Array.new(@resources.size)
    mutex   = Mutex.new

    @resources.each_slice(MAX_THREADS).each_with_index do |batch, batch_idx|
      offset  = batch_idx * MAX_THREADS
      threads = batch.each_with_index.map do |resource, local_idx|
        Thread.new do
          result = fetch_with_rate_limit(resource[:url])

          mutex.synchronize do
            results[offset + local_idx] = { url: resource[:url], type: resource[:type], result: result }
          end
        end
      end

      threads.each(&:join)
    end

    results
  end

  private

  def fetch_with_rate_limit(url)
    domain = extract_domain(url)
    @rate_limiter.with_domain(domain) { ResourceFetcher.call(url) }
  rescue => e
    Rails.logger.warn("ParallelResourceFetcher: unexpected error for #{url} — #{e.class}: #{e.message}")
    nil
  end

  def extract_domain(url)
    Addressable::URI.parse(url).host.to_s.downcase
  rescue Addressable::URI::InvalidURIError
    url
  end
end
