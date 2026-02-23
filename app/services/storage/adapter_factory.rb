# frozen_string_literal: true

module Storage
  # Builds the appropriate storage adapter based on the STORAGE_ADAPTER env var.
  # Defaults to LocalAdapter so the app works out of the box without any AWS config.
  #
  # Set STORAGE_ADAPTER=s3 in production (along with AWS_BUCKET / AWS_REGION).
  module AdapterFactory
    def self.build
      case ENV.fetch("STORAGE_ADAPTER", "local")
      when "s3"
        S3Adapter.new
      else
        LocalAdapter.new
      end
    end
  end
end
