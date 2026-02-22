# frozen_string_literal: true

class HtmlFetcher
  include Retryable

  USER_AGENT = "WebContentArchiver/1.0 (+https://github.com/storylane/web-content-archiver)"
  MAX_REDIRECTS = 5
  DEFAULT_TIMEOUT = 30

  # Raised for generic fetch failures (non-200 responses other than 404)
  class FetchError < StandardError
    attr_reader :status_code

    def initialize(message, status_code: nil)
      super(message)
      @status_code = status_code
    end
  end

  # Raised when the request times out
  class TimeoutError < FetchError; end

  # Raised when the resource returns 404
  class NotFoundError < FetchError; end

  def self.call(url, timeout: DEFAULT_TIMEOUT)
    new(url, timeout: timeout).call
  end

  def initialize(url, timeout: DEFAULT_TIMEOUT)
    @url = url
    @timeout = timeout
  end

  # Fetches an HTML page, following redirects, with retry on transient failures.
  #
  # @return [Hash] with keys :body, :content_type, :final_url
  # @raise [HtmlFetcher::TimeoutError] if the request times out
  # @raise [HtmlFetcher::NotFoundError] if the server returns 404
  # @raise [HtmlFetcher::FetchError] for other non-successful responses
  def call
    with_retry do
      response = HTTParty.get(
        @url,
        headers: { "User-Agent" => USER_AGENT },
        follow_redirects: true,
        no_follow: false,
        timeout: @timeout,
        max_retries: 0
      )

      handle_response(response, @url)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise TimeoutError.new("Request timed out fetching: #{@url}")
  end

  private

  def handle_response(response, url)
    case response.code
    when 200..299
      {
        body: response.body,
        content_type: extract_content_type(response),
        final_url: response.request.last_uri.to_s
      }
    when 404
      raise NotFoundError.new("Page not found: #{url}", status_code: 404)
    else
      raise FetchError.new(
        "Failed to fetch #{url}: HTTP #{response.code}",
        status_code: response.code
      )
    end
  end

  def extract_content_type(response)
    content_type = response.headers["content-type"] || ""
    content_type.split(";").first.to_s.strip
  end
end
