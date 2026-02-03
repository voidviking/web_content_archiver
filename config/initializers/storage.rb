# frozen_string_literal: true

# Storage Adapter Configuration
#
# This application uses a storage adapter pattern to handle file uploads.
# You can switch between local filesystem storage and AWS S3 storage.
#
# ## Local Storage (Default)
# Files are stored in storage/archived_assets/
# No additional configuration required.
#
# ## S3 Storage
# To use S3, set the following environment variables:
#   USE_S3=true
#   AWS_BUCKET=your-bucket-name
#   AWS_REGION=us-east-1 (optional, defaults to us-east-1)
#   AWS_ACCESS_KEY_ID=your-access-key-id
#   AWS_SECRET_ACCESS_KEY=your-secret-access-key
#
# Note: In production with IAM roles, you can omit AWS_ACCESS_KEY_ID
# and AWS_SECRET_ACCESS_KEY - the SDK will use instance credentials.
#
Rails.application.config.to_prepare do
  Rails.application.config.storage_adapter =
    if ENV["USE_S3"] == "true"
      Storage::S3Adapter.new
    else
      Storage::LocalAdapter.new
    end
end
