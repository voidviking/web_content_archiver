# frozen_string_literal: true

# Recursively processes <iframe> elements in an HTML document:
#
#  - src-based iframes  : fetches the iframe URL, processes it, and inlines
#                         the result as a srcdoc attribute (removing src).
#  - srcdoc-based iframes: processes the inline HTML in place.
#  - Nested iframes     : recursion is capped at MAX_DEPTH to prevent loops.
#
# Each iframe's external assets (CSS, JS, images) are extracted, fetched in
# parallel, uploaded to storage, and their URLs rewritten before inlining —
# the same pipeline as the main page.  Resource records are created for every
# uploaded asset so the archive has a complete picture of everything stored.
#
# Failed iframe fetches are logged and skipped; the original <iframe> element
# is left untouched so the page still renders meaningfully.
#
# Usage (called by ArchiveProcessorJob):
#   html = IframeProcessor.call(html, base_url:, storage:, archive:)
class IframeProcessor
  MAX_DEPTH = 3

  def self.call(html, base_url:, storage:, archive:, depth: 0)
    new(html, base_url: base_url, storage: storage, archive: archive, depth: depth).call
  end

  def initialize(html, base_url:, storage:, archive:, depth: 0)
    @html     = html
    @base_url = Addressable::URI.parse(base_url)
    @storage  = storage
    @archive  = archive
    @depth    = depth
    @doc      = Nokogiri::HTML(@html)
  end

  # @return [String] HTML with all processable iframes inlined as srcdoc
  def call
    return @html if @depth >= MAX_DEPTH

    @doc.css("iframe").each { |iframe| process_iframe(iframe) }

    @doc.to_html
  end

  private

  def process_iframe(iframe)
    if iframe["src"].present?
      process_src_iframe(iframe)
    elsif iframe["srcdoc"].present?
      process_srcdoc_iframe(iframe)
    end
    # iframes with neither src nor srcdoc are left as-is
  end

  # Fetches the iframe src URL and inlines it. On any fetch error the iframe is
  # left unchanged so the rest of the page can still be archived.
  def process_src_iframe(iframe)
    url = resolve(iframe["src"])
    return unless url

    result = HtmlFetcher.call(url)
    inline_iframe(iframe, result[:body], result[:final_url])
  rescue HtmlFetcher::FetchError => e
    Rails.logger.warn("IframeProcessor: skipping iframe #{url} — #{e.class}: #{e.message}")
  end

  # Processes an iframe whose content is already present as a srcdoc attribute.
  # Nokogiri automatically unescapes HTML entities when reading the attribute.
  def process_srcdoc_iframe(iframe)
    inline_iframe(iframe, iframe["srcdoc"], @base_url.to_s)
  end

  # Shared logic: recursively processes iframe HTML, uploads its assets, rewrites
  # URLs, then stores the result as a srcdoc attribute on the iframe element.
  def inline_iframe(iframe, iframe_html, iframe_base_url)
    # 1. Recurse into any nested iframes first
    processed_html = IframeProcessor.call(
      iframe_html,
      base_url: iframe_base_url,
      storage:  @storage,
      archive:  @archive,
      depth:    @depth + 1
    )

    # 2. Extract, fetch, and upload the iframe's own assets
    resources = ResourceExtractor.call(processed_html, base_url: iframe_base_url)
    fetched   = ParallelResourceFetcher.call(resources)
    mapping   = upload_assets(fetched)

    # 3. Rewrite asset URLs inside the iframe HTML
    rewritten_html = UrlRewriter.call(processed_html, mapping)

    # 4. Replace src with the fully-processed srcdoc
    iframe.remove_attribute("src")
    iframe["srcdoc"] = rewritten_html
  end

  # Uploads each fetched asset, creates a Resource record, and returns the
  # { original_url => storage_url } mapping needed for URL rewriting.
  def upload_assets(fetched_resources)
    fetched_resources.each_with_object({}) do |item, mapping|
      next unless item[:result]

      key         = storage_key(item[:url], item[:result][:content_type])
      @storage.upload(key: key, body: item[:result][:body], content_type: item[:result][:content_type])
      storage_url = @storage.url_for(key: key)

      Resource.create!(
        archive:       @archive,
        original_url:  item[:url],
        storage_key:   key,
        storage_url:   storage_url,
        resource_type: item[:type],
        content_type:  item[:result][:content_type],
        file_size:     item[:result][:size]
      )

      # Atomic increment: safe under concurrent writers — issues a single
      # UPDATE … SET resources_count = resources_count + 1 in the database.
      Archive.increment_counter(:resources_count, @archive.id)

      mapping[item[:url]] = storage_url
    end
  end

  def storage_key(url, content_type)
    ext = extract_extension(url, content_type)
    "archives/#{@archive.id}/#{SecureRandom.hex(8)}#{ext}"
  end

  def extract_extension(url, content_type)
    path = Addressable::URI.parse(url).path.to_s
    ext  = File.extname(path.split("?").first)
    return ext if ext.present?

    mime = Mime::Type.lookup(content_type.to_s)
    mime ? ".#{mime.symbol}" : ""
  rescue StandardError
    ""
  end

  def resolve(url)
    return nil if url.blank?

    @base_url.join(Addressable::URI.parse(url)).to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
