# frozen_string_literal: true

# Orchestrates the full archiving pipeline for a single URL:
#
#   1. Fetch the HTML page
#   2. Extract all external resource URLs (CSS, JS, images, fonts)
#   3. Fetch all resources in parallel (rate-limited per domain)
#   4. Upload each asset to storage and create Resource records
#   5. Rewrite the HTML so every asset URL points to its storage location
#   6. Persist the rewritten HTML and mark the archive completed
#
# On any failure the archive is marked :failed with an error_message and the
# exception is re-raised so Sidekiq can apply its retry policy.
class ArchiveProcessorJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: 3, dead: false

  # If the archive row was deleted between enqueue and execution, discard silently.
  discard_on ActiveRecord::RecordNotFound

  def perform(archive_id)
    @archive = Archive.find(archive_id)

    return if @archive.status_completed?

    # Atomic status claim: only the first worker to reach this point transitions
    # the archive to :processing. Subsequent workers (duplicate enqueue, retries
    # on a still-pending record) get rows_updated == 0 and exit cleanly.
    rows_updated = Archive
      .where(id: @archive.id, status: [ :pending, :failed ])
      .update_all(status: Archive.statuses[:processing], updated_at: Time.current)

    return if rows_updated == 0

    process_archive
  rescue => e
    handle_failure(e)
    raise
  end

  private

  def process_archive
    fetch_result = HtmlFetcher.call(@archive.url)
    html         = fetch_result[:body]
    base_url     = fetch_result[:final_url]

    resources         = ResourceExtractor.call(html, base_url: base_url)
    fetched_resources = ParallelResourceFetcher.call(resources)

    mapping = upload_assets(fetched_resources)

    rewritten_html = UrlRewriter.call(html, mapping)

    # Atomic completion: only the one worker whose WHERE matches (status still
    # :processing) will write. Any concurrent worker gets rows_updated == 0.
    Archive
      .where(id: @archive.id, status: :processing)
      .update_all(
        status:     Archive.statuses[:completed],
        content:    rewritten_html,
        updated_at: Time.current
      )
  end

  # Uploads each successfully fetched asset to storage, creates a Resource record,
  # and returns a mapping of { original_url => storage_url } for URL rewriting.
  def upload_assets(fetched_resources)
    fetched_resources.each_with_object({}) do |item, mapping|
      next unless item[:result]

      key = generate_storage_key(@archive.id, item[:url], item[:result][:content_type])
      storage.upload(key: key, body: item[:result][:body], content_type: item[:result][:content_type])
      storage_url = storage.url_for(key: key)

      Resource.create!(
        archive:       @archive,
        original_url:  item[:url],
        storage_key:   key,
        storage_url:   storage_url,
        resource_type: item[:type],
        content_type:  item[:result][:content_type],
        file_size:     item[:result][:size]
      )

      mapping[item[:url]] = storage_url
    end
  end

  def handle_failure(error)
    Rails.logger.error(
      "ArchiveProcessorJob failed for archive ##{@archive&.id}: " \
      "#{error.class}: #{error.message}"
    )
    return unless @archive&.id

    # Class-level update_all bypasses optimistic locking and operates on a
    # fresh WHERE id = ? — safe even when @archive is stale after update_all.
    Archive.where(id: @archive.id).update_all(
      status:        Archive.statuses[:failed],
      error_message: error.message.to_s.first(500),
      updated_at:    Time.current
    )
  end

  def storage
    @storage ||= Storage::AdapterFactory.build
  end

  # Derives a unique storage key for an asset.
  # Prefers the file extension from the URL path; falls back to the MIME type.
  def generate_storage_key(archive_id, url, content_type)
    ext = extract_extension(url, content_type)
    "archives/#{archive_id}/#{SecureRandom.hex(8)}#{ext}"
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
end
