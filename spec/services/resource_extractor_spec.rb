# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResourceExtractor do
  let(:base_url) { "https://example.com" }

  def extract(html)
    described_class.call(html, base_url: base_url)
  end

  def urls_of_type(results, type)
    results.select { |r| r[:type] == type }.map { |r| r[:url] }
  end

  describe ".call" do
    context "stylesheets" do
      it "extracts <link rel='stylesheet'> hrefs" do
        html = '<link rel="stylesheet" href="/styles/main.css">'
        result = extract(html)

        expect(urls_of_type(result, :stylesheet)).to include("https://example.com/styles/main.css")
      end

      it "extracts stylesheet with absolute URL" do
        html = '<link rel="stylesheet" href="https://cdn.example.com/lib.css">'
        result = extract(html)

        expect(urls_of_type(result, :stylesheet)).to include("https://cdn.example.com/lib.css")
      end

      it "extracts preload stylesheet links" do
        html = '<link rel="preload" as="style" href="/fonts/preload.css">'
        result = extract(html)

        expect(urls_of_type(result, :stylesheet)).to include("https://example.com/fonts/preload.css")
      end
    end

    context "scripts" do
      it "extracts <script src> attributes" do
        html = '<script src="/js/app.js"></script>'
        result = extract(html)

        expect(urls_of_type(result, :script)).to include("https://example.com/js/app.js")
      end

      it "extracts script with absolute URL" do
        html = '<script src="https://cdn.example.com/analytics.js"></script>'
        result = extract(html)

        expect(urls_of_type(result, :script)).to include("https://cdn.example.com/analytics.js")
      end

      it "skips inline scripts (no src attribute)" do
        html = "<script>var x = 1;</script>"
        result = extract(html)

        expect(urls_of_type(result, :script)).to be_empty
      end
    end

    context "images" do
      it "extracts <img src> attributes" do
        html = '<img src="/images/logo.png">'
        result = extract(html)

        expect(urls_of_type(result, :image)).to include("https://example.com/images/logo.png")
      end

      it "extracts srcset URLs" do
        html = '<img srcset="/img@1x.png 1x, /img@2x.png 2x" src="/img@1x.png">'
        result = extract(html)
        image_urls = urls_of_type(result, :image)

        expect(image_urls).to include("https://example.com/img@1x.png")
        expect(image_urls).to include("https://example.com/img@2x.png")
      end

      it "extracts multiple srcset entries including width descriptors" do
        html = '<img srcset="/small.jpg 480w, /medium.jpg 800w, /large.jpg 1200w">'
        result = extract(html)
        image_urls = urls_of_type(result, :image)

        expect(image_urls).to include(
          "https://example.com/small.jpg",
          "https://example.com/medium.jpg",
          "https://example.com/large.jpg"
        )
      end

      it "extracts favicon link" do
        html = '<link rel="icon" href="/favicon.ico">'
        result = extract(html)

        expect(urls_of_type(result, :image)).to include("https://example.com/favicon.ico")
      end

      it "extracts apple-touch-icon" do
        html = '<link rel="apple-touch-icon" href="/apple-icon.png">'
        result = extract(html)

        expect(urls_of_type(result, :image)).to include("https://example.com/apple-icon.png")
      end
    end

    context "fonts from <style> tags" do
      it "extracts font url() from @font-face blocks" do
        html = <<~HTML
          <style>
            @font-face {
              font-family: "MyFont";
              src: url("/fonts/myfont.woff2") format("woff2");
            }
          </style>
        HTML

        result = extract(html)
        expect(urls_of_type(result, :font)).to include("https://example.com/fonts/myfont.woff2")
      end

      it "identifies woff fonts" do
        html = '<style>@font-face { src: url("/font.woff"); }</style>'
        result = extract(html)

        expect(urls_of_type(result, :font)).to include("https://example.com/font.woff")
      end

      it "identifies ttf fonts" do
        html = '<style>@font-face { src: url("/font.ttf"); }</style>'
        result = extract(html)

        expect(urls_of_type(result, :font)).to include("https://example.com/font.ttf")
      end

      it "extracts background-image urls as :other" do
        html = '<style>body { background-image: url("/bg.jpg"); }</style>'
        result = extract(html)

        expect(urls_of_type(result, :other)).to include("https://example.com/bg.jpg")
      end
    end

    context "urls from inline styles" do
      it "extracts url() from style attributes" do
        html = '<div style="background: url(/bg.png)"></div>'
        result = extract(html)

        expect(result.map { |r| r[:url] }).to include("https://example.com/bg.png")
      end

      it "handles quoted urls in style attributes" do
        html = '<div style="background: url(\'/hero.jpg\')"></div>'
        result = extract(html)

        expect(result.map { |r| r[:url] }).to include("https://example.com/hero.jpg")
      end
    end

    context "URL resolution" do
      it "converts relative URLs to absolute using base_url" do
        html = '<img src="/images/photo.jpg">'
        result = extract(html)

        expect(result.first[:url]).to eq("https://example.com/images/photo.jpg")
      end

      it "resolves relative paths without leading slash" do
        html = '<img src="images/photo.jpg">'
        result = described_class.call(html, base_url: "https://example.com/page/")

        expect(result.first[:url]).to eq("https://example.com/page/images/photo.jpg")
      end

      it "keeps absolute URLs unchanged" do
        html = '<img src="https://cdn.example.com/image.png">'
        result = extract(html)

        expect(result.first[:url]).to eq("https://cdn.example.com/image.png")
      end
    end

    context "skippable URLs" do
      it "skips data: URLs" do
        html = '<img src="data:image/png;base64,iVBORw0KGgo=">'
        result = extract(html)

        expect(result).to be_empty
      end

      it "skips blob: URLs" do
        html = '<img src="blob:https://example.com/some-uuid">'
        result = extract(html)

        expect(result).to be_empty
      end

      it "skips javascript: URLs" do
        html = '<a href="javascript:void(0)">click</a>'
        result = extract(html)

        expect(result).to be_empty
      end
    end

    context "deduplication" do
      it "returns unique URLs only" do
        html = <<~HTML
          <link rel="stylesheet" href="/style.css">
          <link rel="stylesheet" href="/style.css">
        HTML

        result = extract(html)
        urls = result.map { |r| r[:url] }

        expect(urls.count("https://example.com/style.css")).to eq(1)
      end
    end

    context "malformed HTML" do
      it "does not raise on malformed HTML" do
        html = "<html><body><img src='/img.png'><p>unclosed<br></body>"
        expect { extract(html) }.not_to raise_error
      end

      it "still extracts valid resources from malformed HTML" do
        html = "<img src='/logo.png'><<<<broken"
        result = extract(html)

        expect(urls_of_type(result, :image)).to include("https://example.com/logo.png")
      end
    end
  end
end
