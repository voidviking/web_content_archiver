# frozen_string_literal: true

require "rails_helper"

RSpec.describe HtmlFetcher do
  let(:url) { "https://example.com/page" }
  let(:html_body) { "<html><body><h1>Hello</h1></body></html>" }

  describe ".call" do
    context "with a successful response" do
      before do
        stub_request(:get, url)
          .to_return(
            status: 200,
            body: html_body,
            headers: { "Content-Type" => "text/html; charset=utf-8" }
          )
      end

      it "returns the response body" do
        result = described_class.call(url)
        expect(result[:body]).to eq(html_body)
      end

      it "returns the content type without charset" do
        result = described_class.call(url)
        expect(result[:content_type]).to eq("text/html")
      end

      it "returns the final URL after any redirects" do
        result = described_class.call(url)
        expect(result[:final_url]).to eq(url)
      end

      it "sends the correct User-Agent header" do
        described_class.call(url)

        expect(WebMock).to have_requested(:get, url)
          .with(headers: { "User-Agent" => HtmlFetcher::USER_AGENT })
      end
    end

    context "with a redirect" do
      let(:redirect_url) { "https://example.com/redirected-page" }

      before do
        stub_request(:get, url)
          .to_return(status: 301, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(
            status: 200,
            body: html_body,
            headers: { "Content-Type" => "text/html" }
          )
      end

      it "follows the redirect and returns body" do
        result = described_class.call(url)
        expect(result[:body]).to eq(html_body)
      end

      it "returns the final URL after redirect" do
        result = described_class.call(url)
        expect(result[:final_url]).to eq(redirect_url)
      end
    end

    context "with a 404 response" do
      before do
        stub_request(:get, url).to_return(status: 404)
      end

      it "raises NotFoundError" do
        expect { described_class.call(url) }.to raise_error(HtmlFetcher::NotFoundError)
      end

      it "includes the URL in the error message" do
        expect { described_class.call(url) }.to raise_error(HtmlFetcher::NotFoundError, /#{Regexp.escape(url)}/)
      end
    end

    context "with a 500 response" do
      subject(:fetcher) { described_class.new(url) }

      before do
        stub_request(:get, url).to_return(status: 500)
      end

      it "raises FetchError" do
        allow(fetcher).to receive(:sleep)
        expect { fetcher.call }.to raise_error(HtmlFetcher::FetchError)
      end

      it "includes the status code in the error message" do
        allow(fetcher).to receive(:sleep)
        expect { fetcher.call }.to raise_error(HtmlFetcher::FetchError, /500/)
      end
    end

    context "with a timeout" do
      before do
        stub_request(:get, url).to_timeout
      end

      it "raises TimeoutError" do
        expect { described_class.call(url) }.to raise_error(HtmlFetcher::TimeoutError)
      end

      it "includes the URL in the error message" do
        expect { described_class.call(url) }.to raise_error(HtmlFetcher::TimeoutError, /#{Regexp.escape(url)}/)
      end
    end

    context "with custom timeout" do
      it "respects the configured timeout" do
        stub_request(:get, url).to_return(status: 200, body: html_body)

        expect { described_class.call(url, timeout: 5) }.not_to raise_error
      end
    end
  end
end
