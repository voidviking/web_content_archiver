# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Retry when optimistic locking detects a concurrent update on the same record.
  # The job reloads fresh data on the next attempt and re-evaluates its guards.
  retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 3

  # Retry on transient database deadlocks.
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Discard jobs that reference records deleted before the job could run.
  discard_on ActiveJob::DeserializationError
end
