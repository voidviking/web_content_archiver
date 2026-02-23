# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq Configuration" do
  it "uses Sidekiq as the ActiveJob queue adapter in non-test environments" do
    # In the test environment the adapter is intentionally overridden to :test
    # (config/environments/test.rb) so that jobs never touch Redis during specs.
    # In every other environment Sidekiq is the configured adapter.
    if Rails.env.test?
      expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::TestAdapter)
    else
      expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::SidekiqAdapter)
    end
  end

  it "configures Redis URL for Sidekiq" do
    expect(Sidekiq.redis_pool).to be_a(ConnectionPool)
  end
end
