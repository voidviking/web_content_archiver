# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResourceFetcher do
  subject(:fetcher) { described_class.new }

  let(:url) { "https://example.com/assets/style.css" }
  let(:css_body) { "body { margin: 0; padding: 0; }" }

  describe "#fetch" do
    context "with a successful response" do
      before do
        stub_request(:get, url)
          .to_return(
            status: 200,
            body: css_body,
            headers: { "Content-Type" => "text/css; charset=utf-8" }
          )
      end

      it "returns the response body" do
        result = fetcher.fetch(url)
        expect(result[:body]).to eq(css_body)
      end

      it "returns the content type without charset" do
        result = fetcher.fetch(url)
        expect(result[:content_type]).to eq("text/css")
      end

      it "returns the byte size of the body" do
        result = fetcher.fetch(url)
        expect(result[:size]).to eq(css_body.bytesize)
      end

      it "sends the correct User-Agent header" do
        fetcher.fetch(url)

        expect(WebMock).to have_requested(:get, url)
          .with(headers: { "User-Agent" => ResourceFetcher::USER_AGENT })
      end
    end

    context "with binary content (images, fonts)" do
      let(:image_url) { "https://example.com/logo.png" }
      let(:binary_body) { "\x89PNG\r\n\x1a\n".b }

      before do
        stub_request(:get, image_url)
          .to_return(
            status: 200,
            body: binary_body,
            headers: { "Content-Type" => "image/png" }
          )
      end

      it "returns binary content correctly" do
        result = fetcher.fetch(image_url)
        expect(result[:body].encoding).to eq(Encoding::BINARY)
      end

      it "returns correct content type for images" do
        result = fetcher.fetch(image_url)
        expect(result[:content_type]).to eq("image/png")
      end
    end

    context "with a 404 response" do
      before do
        stub_request(:get, url).to_return(status: 404)
      end

      it "returns nil instead of raising" do
        result = fetcher.fetch(url)
        expect(result).to be_nil
      end
    end

    context "with a 500 response" do
      before do
        stub_request(:get, url).to_return(status: 500)
      end

      it "returns nil after exhausting retries" do
        allow(fetcher).to receive(:sleep)
        result = fetcher.fetch(url)
        expect(result).to be_nil
      end
    end

    context "with a timeout" do
      before do
        stub_request(:get, url).to_timeout
      end

      it "returns nil instead of raising" do
        result = fetcher.fetch(url)
        expect(result).to be_nil
      end

      it "logs a warning" do
        expect(Rails.logger).to receive(:warn).with(/failed to fetch/)
        fetcher.fetch(url)
      end
    end

    context "with a connection error" do
      before do
        stub_request(:get, url).to_raise(Errno::ECONNREFUSED)
      end

      it "returns nil instead of raising" do
        allow(fetcher).to receive(:sleep)
        result = fetcher.fetch(url)
        expect(result).to be_nil
      end

      it "logs a warning with the error class" do
        allow(fetcher).to receive(:sleep)
        expect(Rails.logger).to receive(:warn).with(/Errno::ECONNREFUSED/)
        fetcher.fetch(url)
      end
    end
  end
end
