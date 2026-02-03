# frozen_string_literal: true

module Storage
  # Base interface for storage adapters
  # Implementations must provide methods for uploading files and generating URLs
  class Base
    # Upload content to storage
    #
    # @param key [String] Unique identifier for the file
    # @param body [String, IO] File content to upload
    # @param content_type [String] MIME type of the content
    # @return [String] The storage key used
    # @raise [NotImplementedError] if not implemented by subclass
    def upload(key:, body:, content_type:)
      raise NotImplementedError, "#{self.class} must implement #upload"
    end

    # Generate a publicly accessible URL for a stored file
    #
    # @param key [String] Storage key for the file
    # @return [String] Public URL to access the file
    # @raise [NotImplementedError] if not implemented by subclass
    def url_for(key:)
      raise NotImplementedError, "#{self.class} must implement #url_for"
    end

    # Check if a file exists in storage
    #
    # @param key [String] Storage key for the file
    # @return [Boolean] true if file exists
    def exists?(key:)
      raise NotImplementedError, "#{self.class} must implement #exists?"
    end
  end
end
