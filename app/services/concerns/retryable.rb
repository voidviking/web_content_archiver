# frozen_string_literal: true

module Retryable
  TRANSIENT_HTTP_STATUSES = [ 429, 500, 502, 503, 504 ].freeze
  TRANSIENT_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED ].freeze

  # Executes a block with retry logic and exponential backoff.
  #
  # @param max_attempts [Integer] total number of attempts (including the first)
  # @param base_delay [Float] initial wait in seconds, doubled on each retry
  # @param transient_statuses [Array<Integer>] HTTP status codes worth retrying
  # @yieldparam attempt [Integer] current attempt number (1-based)
  # @yieldreturn [Object] result of the block on success
  # @raise [StandardError] re-raises the last error after all attempts are exhausted
  def with_retry(max_attempts: 3, base_delay: 1.0, transient_statuses: TRANSIENT_HTTP_STATUSES)
    attempts = 0

    begin
      attempts += 1
      yield attempts
    rescue *TRANSIENT_ERRORS => e
      raise unless attempts < max_attempts

      sleep(backoff_delay(attempts, base_delay))
      retry
    rescue => e
      raise unless transient_status_error?(e, transient_statuses) && attempts < max_attempts

      sleep(backoff_delay(attempts, base_delay))
      retry
    end
  end

  private

  def backoff_delay(attempt, base_delay)
    base_delay * (2**(attempt - 1))
  end

  def transient_status_error?(error, transient_statuses)
    return false unless error.respond_to?(:response) && error.response.respond_to?(:code)

    transient_statuses.include?(error.response.code.to_i)
  end
end
