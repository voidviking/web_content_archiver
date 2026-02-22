# frozen_string_literal: true

require "rails_helper"

RSpec.describe UrlRewriter do
  let(:original_css_url) { "https://example.com/style.css" }
  let(:original_img_url) { "https://example.com/logo.png" }
  let(:storage_css_url) { "/archived_assets/abc123.css" }
  let(:storage_img_url) { "/archived_assets/def456.png" }
  let(:mapping) do
    {
      original_css_url => storage_css_url,
      original_img_url => storage_img_url
    }
  end

  def rewrite(html, custom_mapping = mapping)
    described_class.call(html, custom_mapping)
  end

  describe ".call" do
    context "href attributes" do
      it "replaces matched href on <link> tags" do
        html = %(<link rel="stylesheet" href="#{original_css_url}">)
        result = rewrite(html)

        expect(result).to include(storage_css_url)
        expect(result).not_to include(original_css_url)
      end

      it "does not replace unmatched href" do
        html = '<link rel="stylesheet" href="https://other.com/style.css">'
        result = rewrite(html)

        expect(result).to include("https://other.com/style.css")
      end
    end

    context "src attributes" do
      it "replaces matched src on <img> tags" do
        html = %(<img src="#{original_img_url}" alt="logo">)
        result = rewrite(html)

        expect(result).to include(storage_img_url)
        expect(result).not_to include(original_img_url)
      end

      it "replaces matched src on <script> tags" do
        original_js = "https://example.com/app.js"
        storage_js = "/archived_assets/app.js"
        html = %(<script src="#{original_js}"></script>)
        result = rewrite(html, { original_js => storage_js })

        expect(result).to include(storage_js)
        expect(result).not_to include(original_js)
      end
    end

    context "srcset attributes" do
      it "replaces matched URLs in srcset" do
        html = %(<img srcset="#{original_img_url} 1x, https://example.com/logo@2x.png 2x">)
        result = rewrite(html)

        expect(result).to include("#{storage_img_url} 1x")
        expect(result).not_to include("#{original_img_url} 1x")
      end

      it "preserves width/density descriptors after replacement" do
        original_2x = "https://example.com/logo@2x.png"
        storage_2x = "/archived_assets/logo2x.png"
        html = %(<img srcset="#{original_img_url} 1x, #{original_2x} 2x">)
        result = rewrite(html, { original_img_url => storage_img_url, original_2x => storage_2x })

        expect(result).to include("#{storage_img_url} 1x")
        expect(result).to include("#{storage_2x} 2x")
      end

      it "preserves unmatched entries in srcset" do
        html = %(<img srcset="#{original_img_url} 1x, https://cdn.other.com/img.png 2x">)
        result = rewrite(html)

        expect(result).to include("https://cdn.other.com/img.png 2x")
      end
    end

    context "inline style attributes" do
      it "replaces url() in style attributes" do
        html = %(<div style="background: url(#{original_img_url})">)
        result = rewrite(html)

        expect(result).to include("url(#{storage_img_url})")
        expect(result).not_to include("url(#{original_img_url})")
      end

      it "preserves quotes in url() if originally quoted" do
        html = %(<div style="background: url('#{original_img_url}')">)
        result = rewrite(html)

        expect(result).to include("url('#{storage_img_url}')")
      end
    end

    context "<style> tag content" do
      it "replaces url() inside <style> tags" do
        html = "<style>body { background: url(#{original_img_url}); }</style>"
        result = rewrite(html)

        expect(result).to include("url(#{storage_img_url})")
        expect(result).not_to include("url(#{original_img_url})")
      end

      it "replaces multiple url() occurrences in a <style> tag" do
        html = <<~HTML
          <style>
            .logo { background: url(#{original_img_url}); }
            @import url(#{original_css_url});
          </style>
        HTML

        result = rewrite(html)
        expect(result).to include("url(#{storage_img_url})")
        expect(result).to include("url(#{storage_css_url})")
      end
    end

    context "with multiple replacements" do
      it "replaces all matched URLs in one pass" do
        html = <<~HTML
          <link rel="stylesheet" href="#{original_css_url}">
          <img src="#{original_img_url}">
        HTML

        result = rewrite(html)
        expect(result).to include(storage_css_url)
        expect(result).to include(storage_img_url)
        expect(result).not_to include(original_css_url)
        expect(result).not_to include(original_img_url)
      end

      it "replaces all occurrences of the same URL" do
        html = <<~HTML
          <img src="#{original_img_url}">
          <img src="#{original_img_url}">
        HTML

        result = rewrite(html)
        expect(result.scan(storage_img_url).count).to eq(2)
        expect(result).not_to include(original_img_url)
      end
    end

    context "with an empty mapping" do
      it "returns the original HTML unchanged" do
        html = %(<img src="#{original_img_url}">)
        result = described_class.call(html, {})

        expect(result).to include(original_img_url)
      end
    end

    context "with unmatched URLs" do
      it "leaves unmatched URLs untouched" do
        html = '<img src="https://unmatched.com/image.png">'
        result = rewrite(html)

        expect(result).to include("https://unmatched.com/image.png")
      end
    end
  end
end
