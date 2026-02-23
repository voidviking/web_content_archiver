# frozen_string_literal: true

require "rails_helper"

RSpec.describe DistributedLock do
  let(:lock_manager) { instance_double(Redlock::Client) }
  let(:lock_info) { { validity: 29_000, resource: "lock:test_key", value: SecureRandom.hex } }

  before do
    allow(Redlock::Client).to receive(:new).and_return(lock_manager)
  end

  describe ".acquire" do
    context "when the lock is available" do
      before do
        allow(lock_manager).to receive(:lock).and_return(lock_info)
        allow(lock_manager).to receive(:unlock)
      end

      it "yields control to the block" do
        expect { |b| described_class.acquire("test_key", &b) }.to yield_control
      end

      it "returns the block's value" do
        result = described_class.acquire("test_key") { 42 }
        expect(result).to eq(42)
      end

      it "unlocks the resource after the block completes" do
        described_class.acquire("test_key") { "work done" }
        expect(lock_manager).to have_received(:unlock).with(lock_info)
      end

      it "unlocks even if the block raises an exception" do
        described_class.acquire("test_key") { raise "something went wrong" } rescue nil
        expect(lock_manager).to have_received(:unlock).with(lock_info)
      end

      it "prefixes the Redis key with 'lock:'" do
        described_class.acquire("archive:example.com") { }
        expect(lock_manager).to have_received(:lock).with("lock:archive:example.com", anything)
      end

      it "uses the default TTL when none is provided" do
        described_class.acquire("test_key") { }
        expect(lock_manager).to have_received(:lock).with(anything, DistributedLock::DEFAULT_TTL_MS)
      end

      it "uses a custom TTL when provided" do
        described_class.acquire("test_key", ttl: 5_000) { }
        expect(lock_manager).to have_received(:lock).with(anything, 5_000)
      end
    end

    context "when the lock is already held by another process" do
      before do
        allow(lock_manager).to receive(:lock).and_return(nil)
        allow(lock_manager).to receive(:unlock)
      end

      it "does not yield" do
        expect { |b| described_class.acquire("test_key", &b) }.not_to yield_control
      end

      it "returns nil" do
        result = described_class.acquire("test_key") { "should not run" }
        expect(result).to be_nil
      end

      it "does not call unlock" do
        described_class.acquire("test_key") { }
        expect(lock_manager).not_to have_received(:unlock)
      end
    end
  end
end
