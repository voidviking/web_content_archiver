# frozen_string_literal: true

class Archive < ApplicationRecord
  # Associations
  has_many :resources, dependent: :destroy

  # Enums
  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, prefix: true

  # Validations
  validates :url, presence: true, uniqueness: true
  validates :url, format: {
    with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
    message: "must be a valid HTTP or HTTPS URL"
  }
  validates :status, presence: true

  # Callbacks
  before_validation :normalize_url

  private

  def normalize_url
    return if url.blank?

    # Parse and normalize the URL
    uri = Addressable::URI.parse(url)

    # Normalize scheme to lowercase
    uri.scheme = uri.scheme&.downcase

    # Normalize host to lowercase
    uri.host = uri.host&.downcase

    # Sort query parameters for consistency
    if uri.query_values
      uri.query_values = uri.query_values.sort.to_h
    end

    # Remove fragment
    uri.fragment = nil

    # Normalize the URI
    normalized = uri.normalize.to_s

    # Remove trailing slash unless it's just the root or there are query params
    if normalized.end_with?("/") && !normalized.match?(%r{^https?://[^/]+/$})
      normalized = normalized.chomp("/")
    end

    self.url = normalized
  rescue Addressable::URI::InvalidURIError
    # Let validation handle invalid URLs
  end
end
