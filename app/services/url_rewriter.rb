# frozen_string_literal: true

class UrlRewriter
  # @param html [String] archived HTML content
  # @param mapping [Hash] { original_url => storage_url }
  def self.call(html, mapping)
    new(html, mapping).call
  end

  def initialize(html, mapping)
    @html = html
    @mapping = mapping
    @doc = Nokogiri::HTML(@html)
  end

  # Rewrites all matched URLs in the HTML and returns the modified HTML string.
  #
  # @return [String] HTML with original URLs replaced by storage URLs
  def call
    return @html if @mapping.empty?

    rewrite_attributes
    rewrite_style_tags
    @doc.to_html
  end

  private

  # Rewrites src, href, and srcset attributes on HTML elements
  def rewrite_attributes
    # Single-URL attributes
    @doc.css("[src], [href]").each do |node|
      %w[src href].each do |attr|
        next unless node[attr]

        replacement = @mapping[node[attr]]
        node[attr] = replacement if replacement
      end
    end

    # srcset attributes (comma-separated list of "url descriptor" pairs)
    @doc.css("[srcset]").each do |node|
      node["srcset"] = rewrite_srcset(node["srcset"])
    end

    # Inline style attributes: url(...)
    @doc.css("[style]").each do |node|
      node["style"] = rewrite_css_urls(node["style"])
    end
  end

  # Rewrites url(...) references inside <style> tags
  def rewrite_style_tags
    @doc.css("style").each do |node|
      node.content = rewrite_css_urls(node.content)
    end
  end

  # Rewrites a srcset attribute value, replacing matched URLs
  def rewrite_srcset(srcset)
    return srcset if srcset.blank?

    srcset.split(",").map do |part|
      part.strip.then do |p|
        tokens = p.split(/\s+/, 2)
        url = tokens[0]
        descriptor = tokens[1]

        replacement = @mapping[url]
        replacement ? [ replacement, descriptor ].compact.join(" ") : p
      end
    end.join(", ")
  end

  # Rewrites url(...) occurrences within a CSS string
  def rewrite_css_urls(css)
    return css if css.blank?

    css.gsub(/url\(\s*(['"]?)([^'")\s]+)\1\s*\)/) do
      quote = ::Regexp.last_match(1)
      url   = ::Regexp.last_match(2)
      replacement = @mapping[url]
      replacement ? "url(#{quote}#{replacement}#{quote})" : ::Regexp.last_match(0)
    end
  end
end
