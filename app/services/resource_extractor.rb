# frozen_string_literal: true

class ResourceExtractor
  # URL schemes that should never be archived
  SKIPPABLE_SCHEMES = %w[data blob javascript].freeze

  # Maps CSS content-type keywords to resource type symbols
  FONT_FORMATS = %w[woff woff2 ttf otf eot].freeze

  attr_reader :base_url

  # @param html [String] raw HTML content of the page
  # @param base_url [String] absolute URL of the page, used to resolve relative URLs
  def self.call(html, base_url:)
    new(html, base_url: base_url).call
  end

  def initialize(html, base_url:)
    @html = html
    @base_url = Addressable::URI.parse(base_url)
    @doc = Nokogiri::HTML(@html)
  end

  # Parses the HTML and returns all unique external resource URLs with their types.
  #
  # @return [Array<Hash>] array of { url: String, type: Symbol } hashes
  def call
    resources = []
    resources.concat(extract_stylesheets)
    resources.concat(extract_scripts)
    resources.concat(extract_images)
    resources.concat(extract_fonts_from_styles)
    resources.concat(extract_urls_from_inline_styles)

    resources
      .select { |r| valid_url?(r[:url]) }
      .uniq { |r| r[:url] }
  end

  private

  def extract_stylesheets
    @doc.css('link[rel~="stylesheet"][href], link[rel~="preload"][as="style"][href]').map do |node|
      { url: resolve(node["href"]), type: :stylesheet }
    end
  end

  def extract_scripts
    @doc.css("script[src]").map do |node|
      { url: resolve(node["src"]), type: :script }
    end
  end

  def extract_images
    resources = []

    @doc.css("img[src], input[type=image][src], source[src], link[rel~='icon'][href], link[rel~='apple-touch-icon'][href]").each do |node|
      src = node["src"] || node["href"]
      resources << { url: resolve(src), type: :image } if src.present?
    end

    # Parse srcset attributes (multiple URLs per attribute)
    @doc.css("[srcset]").each do |node|
      parse_srcset(node["srcset"]).each do |src_url|
        resources << { url: resolve(src_url), type: :image }
      end
    end

    resources
  end

  def extract_fonts_from_styles
    resources = []

    # Extract from <style> blocks
    @doc.css("style").each do |style_node|
      extract_urls_from_css(style_node.content).each do |url|
        type = font_url?(url) ? :font : :other
        resources << { url: resolve(url), type: type }
      end
    end

    # Extract from <link rel="stylesheet"> loaded inline content (already covered by stylesheets)
    resources
  end

  def extract_urls_from_inline_styles
    resources = []

    @doc.css("[style]").each do |node|
      extract_urls_from_css(node["style"]).each do |url|
        type = font_url?(url) ? :font : :image
        resources << { url: resolve(url), type: type }
      end
    end

    resources
  end

  # Pulls url(...) values out of a CSS string
  def extract_urls_from_css(css_content)
    return [] if css_content.blank?

    css_content.scan(/url\(\s*['"]?([^'")\s]+)['"]?\s*\)/).flatten
  end

  # Parses a srcset attribute into individual URLs (strips width/density descriptors)
  def parse_srcset(srcset)
    return [] if srcset.blank?

    srcset.split(",").map do |part|
      part.strip.split(/\s+/).first
    end.compact
  end

  def resolve(url)
    return nil if url.blank?

    absolute = @base_url.join(Addressable::URI.parse(url))
    absolute.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def valid_url?(url)
    return false if url.blank?

    scheme = Addressable::URI.parse(url).scheme.to_s.downcase
    SKIPPABLE_SCHEMES.none? { |s| scheme.start_with?(s) }
  rescue Addressable::URI::InvalidURIError
    false
  end

  def font_url?(url)
    ext = File.extname(url.to_s.split("?").first).delete(".").downcase
    FONT_FORMATS.include?(ext)
  end
end
