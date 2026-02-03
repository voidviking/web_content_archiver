# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq Configuration" do
  it "uses Sidekiq as the ActiveJob queue adapter" do
    expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::SidekiqAdapter)
  end

  it "configures Redis URL for Sidekiq" do
    expect(Sidekiq.redis_pool).to be_a(ConnectionPool)
  end
end
