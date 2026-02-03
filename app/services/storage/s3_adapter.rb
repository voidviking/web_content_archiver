# frozen_string_literal: true

require "aws-sdk-s3"

module Storage
  # AWS S3 storage adapter
  # Stores files in an S3 bucket with public-read access
  class S3Adapter < Base
    attr_reader :bucket_name, :region

    def initialize
      @bucket_name = ENV.fetch("AWS_BUCKET") { raise "AWS_BUCKET environment variable is required" }
      @region = ENV.fetch("AWS_REGION", "us-east-1")
      @client = build_s3_client
    end

    # Upload content to S3
    #
    # @param key [String] S3 object key
    # @param body [String, IO] File content to upload
    # @param content_type [String] MIME type of the content
    # @return [String] The S3 key used
    def upload(key:, body:, content_type:)
      @client.put_object(
        bucket: bucket_name,
        key: key,
        body: body,
        content_type: content_type,
        acl: "public-read"
      )

      key
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("S3 upload failed for key #{key}: #{e.message}")
      raise StorageError, "Failed to upload to S3: #{e.message}"
    end

    # Generate a publicly accessible URL for an S3 object
    #
    # @param key [String] S3 object key
    # @return [String] Public URL to access the file
    def url_for(key:)
      "https://#{bucket_name}.s3.#{region}.amazonaws.com/#{key}"
    end

    # Check if an object exists in S3
    #
    # @param key [String] S3 object key
    # @return [Boolean] true if object exists
    def exists?(key:)
      @client.head_object(bucket: bucket_name, key: key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error("S3 exists check failed for key #{key}: #{e.message}")
      false
    end

    private

    def build_s3_client
      config = {
        region: region
      }

      # Only set credentials if provided (allows IAM roles in production)
      if ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
        config[:credentials] = Aws::Credentials.new(
          ENV["AWS_ACCESS_KEY_ID"],
          ENV["AWS_SECRET_ACCESS_KEY"]
        )
      end

      Aws::S3::Client.new(config)
    end
  end

  # Custom error for storage operations
  class StorageError < StandardError; end
end
