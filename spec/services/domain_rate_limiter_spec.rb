# frozen_string_literal: true

require "rails_helper"

RSpec.describe DomainRateLimiter do
  subject(:limiter) { described_class.new(max_concurrency: 2) }

  let(:domain) { "cdn.example.com" }

  describe "#acquire and #release" do
    it "starts with a count of zero for an unknown domain" do
      expect(limiter.count(domain)).to eq(0)
    end

    it "increments the count on acquire" do
      limiter.acquire(domain)
      expect(limiter.count(domain)).to eq(1)
    ensure
      limiter.release(domain)
    end

    it "decrements the count on release" do
      limiter.acquire(domain)
      limiter.release(domain)
      expect(limiter.count(domain)).to eq(0)
    end

    it "allows up to max_concurrency simultaneous acquires" do
      limiter.acquire(domain)
      limiter.acquire(domain)
      expect(limiter.count(domain)).to eq(2)
    ensure
      limiter.release(domain)
      limiter.release(domain)
    end

    it "does not mix counts between different domains" do
      other_domain = "other.example.com"
      limiter.acquire(domain)

      expect(limiter.count(domain)).to eq(1)
      expect(limiter.count(other_domain)).to eq(0)
    ensure
      limiter.release(domain)
    end

    it "unblocks a waiting thread once a slot is released" do
      limiter.acquire(domain)
      limiter.acquire(domain)

      acquired_at = nil
      released_at = nil

      waiter = Thread.new do
        limiter.acquire(domain)
        acquired_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ensure
        limiter.release(domain)
      end

      sleep(0.05)
      released_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.release(domain)
      limiter.release(domain)
      waiter.join(2)

      expect(acquired_at).not_to be_nil
      expect(acquired_at).to be >= released_at
    end
  end

  describe "#with_domain" do
    it "yields and returns the block's value" do
      result = limiter.with_domain(domain) { 42 }
      expect(result).to eq(42)
    end

    it "releases the slot even when the block raises" do
      expect { limiter.with_domain(domain) { raise "boom" } }.to raise_error("boom")
      expect(limiter.count(domain)).to eq(0)
    end

    it "increments the count while the block runs and decrements after" do
      counts_during = []

      limiter.with_domain(domain) do
        counts_during << limiter.count(domain)
      end

      expect(counts_during).to eq([ 1 ])
      expect(limiter.count(domain)).to eq(0)
    end
  end

  describe "thread safety" do
    it "handles concurrent acquires across multiple domains without deadlock" do
      domains  = (1..5).map { |i| "domain#{i}.example.com" }
      threads  = domains.flat_map do |d|
        3.times.map do
          Thread.new do
            limiter.with_domain(d) { sleep(0.01) }
          end
        end
      end

      expect { threads.each { |t| t.join(5) } }.not_to raise_error
      domains.each { |d| expect(limiter.count(d)).to eq(0) }
    end
  end
end
