# frozen_string_literal: true

module Storage
  # Local filesystem storage adapter
  # Stores files in the local filesystem under storage/archived_assets/
  class LocalAdapter < Base
    STORAGE_PATH = Rails.root.join("storage", "archived_assets")

    def initialize
      ensure_storage_directory
    end

    # Upload content to local filesystem
    #
    # @param key [String] Unique identifier for the file
    # @param body [String, IO] File content to upload
    # @param content_type [String] MIME type of the content (not used for local storage)
    # @return [String] The storage key used
    def upload(key:, body:, content_type:)
      file_path = STORAGE_PATH.join(key)
      ensure_directory_for(file_path)

      File.open(file_path, "wb") do |file|
        if body.respond_to?(:read)
          IO.copy_stream(body, file)
        else
          file.write(body)
        end
      end

      key
    end

    # Generate a publicly accessible URL for a stored file
    # Returns a relative URL that can be served by Rails
    #
    # @param key [String] Storage key for the file
    # @return [String] URL path to access the file
    def url_for(key:)
      "/archived_assets/#{key}"
    end

    # Check if a file exists in storage
    #
    # @param key [String] Storage key for the file
    # @return [Boolean] true if file exists
    def exists?(key:)
      File.exist?(STORAGE_PATH.join(key))
    end

    # Get the absolute file path for a key
    #
    # @param key [String] Storage key
    # @return [Pathname] Absolute path to the file
    def file_path(key:)
      STORAGE_PATH.join(key)
    end

    private

    def ensure_storage_directory
      FileUtils.mkdir_p(STORAGE_PATH) unless STORAGE_PATH.exist?
    end

    def ensure_directory_for(file_path)
      directory = file_path.dirname
      FileUtils.mkdir_p(directory) unless directory.exist?
    end
  end
end
