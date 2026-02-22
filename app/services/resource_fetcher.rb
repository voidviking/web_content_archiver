# frozen_string_literal: true

class ResourceFetcher
  include Retryable

  USER_AGENT = "WebContentArchiver/1.0 (+https://github.com/storylane/web-content-archiver)"
  DEFAULT_TIMEOUT = 15

  def self.call(url, timeout: DEFAULT_TIMEOUT)
    new(url, timeout: timeout).call
  end

  def initialize(url, timeout: DEFAULT_TIMEOUT)
    @url = url
    @timeout = timeout
  end

  # Fetches a single asset resource (CSS, JS, image, font, etc.)
  # Unlike HtmlFetcher, this returns nil on failure rather than raising,
  # so a single broken asset does not abort the entire archive process.
  #
  # @return [Hash, nil] with keys :body, :content_type, :size, or nil on failure
  def call
    with_retry do
      response = HTTParty.get(
        @url,
        headers: { "User-Agent" => USER_AGENT },
        follow_redirects: true,
        timeout: @timeout,
        max_retries: 0
      )

      return nil unless response.success?

      body = response.body.force_encoding("BINARY")
      {
        body: body,
        content_type: extract_content_type(response),
        size: body.bytesize
      }
    end
  rescue => e
    Rails.logger.warn("ResourceFetcher: failed to fetch #{@url} — #{e.class}: #{e.message}")
    nil
  end

  private

  def extract_content_type(response)
    content_type = response.headers["content-type"] || ""
    content_type.split(";").first.to_s.strip
  end
end
