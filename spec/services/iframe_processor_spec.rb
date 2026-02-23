# frozen_string_literal: true

require "rails_helper"

RSpec.describe IframeProcessor do
  let(:archive)     { create(:archive, :pending) }
  let(:storage)     { instance_double(Storage::LocalAdapter) }
  let(:base_url)    { "https://example.com" }
  let(:iframe_url)  { "https://example.com/embed" }
  let(:iframe_html) { "<html><body><p>Iframe content</p></body></html>" }
  let(:css_url)     { "https://example.com/iframe.css" }

  let(:no_iframe_html) { "<html><body><p>No iframes here</p></body></html>" }

  before do
    allow(storage).to receive(:upload)
    allow(storage).to receive(:url_for).and_return("/storage/asset.css")
    allow(Resource).to receive(:create!)
  end

  def call(html, depth: 0)
    described_class.call(html, base_url: base_url, storage: storage, archive: archive, depth: depth)
  end

  # ─── No iframes ─────────────────────────────────────────────────────────────

  describe "when the HTML has no iframes" do
    it "returns the HTML unchanged" do
      result = call(no_iframe_html)
      expect(result).to include("No iframes here")
    end

    it "does not touch storage" do
      call(no_iframe_html)
      expect(storage).not_to have_received(:upload)
    end
  end

  # ─── src-based iframes ──────────────────────────────────────────────────────

  describe "src-based iframes" do
    let(:html_with_src_iframe) { %(<html><body><iframe src="#{iframe_url}"></iframe></body></html>) }

    before do
      stub_request(:get, iframe_url).to_return(
        status:  200,
        body:    iframe_html,
        headers: { "Content-Type" => "text/html" }
      )
      allow(ResourceExtractor).to receive(:call).and_return([])
      allow(ParallelResourceFetcher).to receive(:call).and_return([])
      allow(UrlRewriter).to receive(:call) { |html, _| html }
    end

    it "removes the src attribute" do
      result = call(html_with_src_iframe)
      expect(result).not_to include('src="https://example.com/embed"')
    end

    it "inlines the fetched content as srcdoc" do
      result = call(html_with_src_iframe)
      expect(result).to include("srcdoc=")
    end

    it "embeds the iframe body content inside srcdoc" do
      result = call(html_with_src_iframe)
      expect(result).to include("Iframe content")
    end

    it "passes the correct base_url to ResourceExtractor" do
      call(html_with_src_iframe)
      expect(ResourceExtractor).to have_received(:call).with(anything, base_url: iframe_url)
    end
  end

  # ─── srcdoc-based iframes ───────────────────────────────────────────────────

  describe "srcdoc-based iframes" do
    let(:escaped_srcdoc) { CGI.escapeHTML(iframe_html) }
    let(:html_with_srcdoc_iframe) { %(<html><body><iframe srcdoc="#{escaped_srcdoc}"></iframe></body></html>) }

    before do
      allow(ResourceExtractor).to receive(:call).and_return([])
      allow(ParallelResourceFetcher).to receive(:call).and_return([])
      allow(UrlRewriter).to receive(:call) { |html, _| html }
    end

    it "keeps the srcdoc attribute" do
      result = call(html_with_srcdoc_iframe)
      expect(result).to include("srcdoc=")
    end

    it "embeds the srcdoc content" do
      result = call(html_with_srcdoc_iframe)
      expect(result).to include("Iframe content")
    end

    it "does not make any HTTP requests" do
      call(html_with_srcdoc_iframe)
      expect(WebMock).not_to have_requested(:get, /.*/)
    end
  end

  # ─── iframe asset uploading ─────────────────────────────────────────────────

  describe "iframe asset processing" do
    let(:html_with_src_iframe) { %(<html><body><iframe src="#{iframe_url}"></iframe></body></html>) }
    let(:css_fetched) do
      { url: css_url, type: :stylesheet, result: { body: "body{}", content_type: "text/css", size: 6 } }
    end

    before do
      stub_request(:get, iframe_url).to_return(
        status:  200,
        body:    iframe_html,
        headers: { "Content-Type" => "text/html" }
      )
      allow(ResourceExtractor).to receive(:call).and_return([ { url: css_url, type: :stylesheet } ])
      allow(ParallelResourceFetcher).to receive(:call).and_return([ css_fetched ])
      allow(UrlRewriter).to receive(:call) { |html, _| html }
    end

    it "uploads iframe assets to storage" do
      call(html_with_src_iframe)
      expect(storage).to have_received(:upload).with(hash_including(content_type: "text/css"))
    end

    it "creates a Resource record for each uploaded asset" do
      call(html_with_src_iframe)
      expect(Resource).to have_received(:create!).with(
        hash_including(original_url: css_url, archive: archive)
      )
    end

    it "increments resources_count once per uploaded asset" do
      expect { call(html_with_src_iframe) }
        .to change { archive.reload.resources_count }.by(1)
    end
  end

  # ─── Depth limit ────────────────────────────────────────────────────────────

  describe "depth limit" do
    let(:html_with_src_iframe) { %(<html><body><iframe src="#{iframe_url}"></iframe></body></html>) }

    it "does not process iframes when depth equals MAX_DEPTH" do
      result = call(html_with_src_iframe, depth: IframeProcessor::MAX_DEPTH)
      # At max depth the HTML is returned as-is, iframe src is preserved
      expect(result).to include('src="https://example.com/embed"')
    end

    it "does not fetch any URLs at max depth" do
      call(html_with_src_iframe, depth: IframeProcessor::MAX_DEPTH)
      expect(WebMock).not_to have_requested(:get, /.*/)
    end
  end

  # ─── Failed iframe fetch ────────────────────────────────────────────────────

  describe "when the iframe URL fails to fetch" do
    let(:html_with_src_iframe) { %(<html><body><iframe src="#{iframe_url}"></iframe></body></html>) }

    before do
      stub_request(:get, iframe_url).to_return(status: 500)
    end

    it "does not raise" do
      expect { call(html_with_src_iframe) }.not_to raise_error
    end

    it "leaves the original src attribute intact" do
      result = call(html_with_src_iframe)
      expect(result).to include('src="https://example.com/embed"')
    end

    it "logs a warning" do
      expect(Rails.logger).to receive(:warn).with(/skipping iframe/)
      call(html_with_src_iframe)
    end
  end

  # ─── Iframe with neither src nor srcdoc ─────────────────────────────────────

  describe "when an iframe has neither src nor srcdoc" do
    let(:html_with_empty_iframe) { "<html><body><iframe id='placeholder'></iframe></body></html>" }

    it "does not raise" do
      expect { call(html_with_empty_iframe) }.not_to raise_error
    end

    it "leaves the iframe element unchanged" do
      result = call(html_with_empty_iframe)
      expect(result).to include("placeholder")
    end
  end

  # ─── Nested iframes ─────────────────────────────────────────────────────────

  describe "nested iframes" do
    let(:nested_iframe_url)  { "https://example.com/nested" }
    let(:nested_iframe_html) { "<html><body><p>Nested</p></body></html>" }
    let(:outer_iframe_html)  { %(<html><body><iframe src="#{nested_iframe_url}"></iframe></body></html>) }
    let(:html_with_src_iframe) { %(<html><body><iframe src="#{iframe_url}"></iframe></body></html>) }

    before do
      stub_request(:get, iframe_url).to_return(
        status:  200,
        body:    outer_iframe_html,
        headers: { "Content-Type" => "text/html" }
      )
      stub_request(:get, nested_iframe_url).to_return(
        status:  200,
        body:    nested_iframe_html,
        headers: { "Content-Type" => "text/html" }
      )
      allow(ResourceExtractor).to receive(:call).and_return([])
      allow(ParallelResourceFetcher).to receive(:call).and_return([])
      allow(UrlRewriter).to receive(:call) { |html, _| html }
    end

    it "fetches and inlines the nested iframe" do
      result = call(html_with_src_iframe)
      expect(result).to include("Nested")
    end

    it "fetches both the outer and nested iframe URLs" do
      call(html_with_src_iframe)
      expect(WebMock).to have_requested(:get, iframe_url)
      expect(WebMock).to have_requested(:get, nested_iframe_url)
    end
  end
end
