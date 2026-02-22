# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParallelResourceFetcher do
  let(:css_url)   { "https://cdn.example.com/style.css" }
  let(:img_url)   { "https://cdn.example.com/logo.png" }
  let(:css_result) { { body: "body{}", content_type: "text/css", size: 6 } }
  let(:img_result) { { body: "\x89PNG".b, content_type: "image/png", size: 4 } }

  let(:resources) do
    [
      { url: css_url, type: :stylesheet },
      { url: img_url, type: :image }
    ]
  end

  let(:rate_limiter) { instance_double(DomainRateLimiter) }

  before do
    allow(rate_limiter).to receive(:with_domain).and_yield
  end

  describe ".call" do
    before do
      stub_request(:get, css_url).to_return(status: 200, body: "body{}", headers: { "Content-Type" => "text/css" })
      stub_request(:get, img_url).to_return(status: 200, body: "\x89PNG".b, headers: { "Content-Type" => "image/png" })
    end

    it "returns one result per input resource" do
      results = described_class.call(resources, rate_limiter: rate_limiter)
      expect(results.size).to eq(2)
    end

    it "preserves the original url and type in each result" do
      results = described_class.call(resources, rate_limiter: rate_limiter)
      urls  = results.map { |r| r[:url] }
      types = results.map { |r| r[:type] }

      expect(urls).to contain_exactly(css_url, img_url)
      expect(types).to contain_exactly(:stylesheet, :image)
    end

    it "includes a non-nil result for successful fetches" do
      results = described_class.call(resources, rate_limiter: rate_limiter)
      results.each { |r| expect(r[:result]).not_to be_nil }
    end

    it "returns an empty array for empty input" do
      expect(described_class.call([], rate_limiter: rate_limiter)).to eq([])
    end
  end

  describe "rate limiter integration" do
    before do
      stub_request(:get, css_url).to_return(status: 200, body: "body{}", headers: { "Content-Type" => "text/css" })
      stub_request(:get, img_url).to_return(status: 200, body: "\x89PNG".b, headers: { "Content-Type" => "image/png" })
    end

    it "calls with_domain once per resource" do
      described_class.call(resources, rate_limiter: rate_limiter)
      expect(rate_limiter).to have_received(:with_domain).exactly(resources.size).times
    end

    it "passes the correct domain to with_domain" do
      described_class.call(resources, rate_limiter: rate_limiter)
      expect(rate_limiter).to have_received(:with_domain).with("cdn.example.com").twice
    end
  end

  describe "failure handling" do
    it "includes nil result for a failed fetch without raising" do
      stub_request(:get, css_url).to_return(status: 200, body: "body{}", headers: { "Content-Type" => "text/css" })
      stub_request(:get, img_url).to_return(status: 404)

      results = described_class.call(resources, rate_limiter: rate_limiter)

      css_entry = results.find { |r| r[:url] == css_url }
      img_entry = results.find { |r| r[:url] == img_url }

      expect(css_entry[:result]).not_to be_nil
      expect(img_entry[:result]).to be_nil
    end

    it "returns nil result and logs a warning when ResourceFetcher raises unexpectedly" do
      stub_request(:get, css_url).to_return(status: 200, body: "body{}", headers: { "Content-Type" => "text/css" })
      allow(ResourceFetcher).to receive(:call).with(img_url).and_raise(RuntimeError, "unexpected!")
      allow(ResourceFetcher).to receive(:call).with(css_url).and_call_original

      expect(Rails.logger).to receive(:warn).with(/unexpected!/)

      results = described_class.call(resources, rate_limiter: rate_limiter)
      img_entry = results.find { |r| r[:url] == img_url }
      expect(img_entry[:result]).to be_nil
    end
  end

  describe "default rate limiter" do
    it "creates a DomainRateLimiter when none is provided" do
      stub_request(:get, css_url).to_return(status: 200, body: "body{}", headers: { "Content-Type" => "text/css" })
      stub_request(:get, img_url).to_return(status: 200, body: "\x89PNG".b, headers: { "Content-Type" => "image/png" })

      expect(DomainRateLimiter).to receive(:new).and_call_original
      described_class.call(resources)
    end
  end
end
