# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storage::S3Adapter do
  subject(:adapter) { described_class.new }

  let(:bucket_name) { "test-bucket" }
  let(:region) { "us-west-2" }
  let(:test_key) { "test-file.txt" }
  let(:test_content) { "Hello, S3!" }
  let(:content_type) { "text/plain" }
  let(:mock_s3_client) { instance_double(Aws::S3::Client) }

  before do
    ENV["AWS_BUCKET"] = bucket_name
    ENV["AWS_REGION"] = region
    ENV["AWS_ACCESS_KEY_ID"] = "test-access-key"
    ENV["AWS_SECRET_ACCESS_KEY"] = "test-secret-key"

    allow(Aws::S3::Client).to receive(:new).and_return(mock_s3_client)
  end

  after do
    ENV.delete("AWS_BUCKET")
    ENV.delete("AWS_REGION")
    ENV.delete("AWS_ACCESS_KEY_ID")
    ENV.delete("AWS_SECRET_ACCESS_KEY")
  end

  describe "#initialize" do
    it "raises an error if AWS_BUCKET is not set" do
      ENV.delete("AWS_BUCKET")

      expect { described_class.new }.to raise_error(RuntimeError, /AWS_BUCKET/)
    end

    it "uses default region if AWS_REGION is not set" do
      ENV.delete("AWS_REGION")

      expect(Aws::S3::Client).to receive(:new).with(
        hash_including(region: "us-east-1")
      ).and_return(mock_s3_client)

      described_class.new
    end

    it "configures AWS credentials from environment variables" do
      expect(Aws::S3::Client).to receive(:new).with(
        hash_including(
          region: region,
          credentials: instance_of(Aws::Credentials)
        )
      ).and_return(mock_s3_client)

      described_class.new
    end
  end

  describe "#upload" do
    it "uploads content to S3 with public-read ACL" do
      expect(mock_s3_client).to receive(:put_object).with(
        bucket: bucket_name,
        key: test_key,
        body: test_content,
        content_type: content_type,
        acl: "public-read"
      )

      result = adapter.upload(key: test_key, body: test_content, content_type: content_type)

      expect(result).to eq(test_key)
    end

    it "handles S3 service errors" do
      allow(mock_s3_client).to receive(:put_object).and_raise(
        Aws::S3::Errors::ServiceError.new(nil, "S3 Error")
      )

      expect {
        adapter.upload(key: test_key, body: test_content, content_type: content_type)
      }.to raise_error(Storage::StorageError, /Failed to upload to S3/)
    end

    it "logs errors when upload fails" do
      allow(mock_s3_client).to receive(:put_object).and_raise(
        Aws::S3::Errors::ServiceError.new(nil, "Network timeout")
      )

      expect(Rails.logger).to receive(:error).with(/S3 upload failed/)

      expect {
        adapter.upload(key: test_key, body: test_content, content_type: content_type)
      }.to raise_error(Storage::StorageError)
    end
  end

  describe "#url_for" do
    it "returns a public S3 URL" do
      url = adapter.url_for(key: test_key)

      expect(url).to eq("https://#{bucket_name}.s3.#{region}.amazonaws.com/#{test_key}")
    end

    it "handles keys with special characters" do
      special_key = "archived/2024/file%20name.txt"
      url = adapter.url_for(key: special_key)

      expect(url).to eq("https://#{bucket_name}.s3.#{region}.amazonaws.com/#{special_key}")
    end
  end

  describe "#exists?" do
    it "returns true when object exists" do
      allow(mock_s3_client).to receive(:head_object).with(
        bucket: bucket_name,
        key: test_key
      )

      expect(adapter.exists?(key: test_key)).to be true
    end

    it "returns false when object does not exist" do
      allow(mock_s3_client).to receive(:head_object).and_raise(
        Aws::S3::Errors::NotFound.new(nil, "Not found")
      )

      expect(adapter.exists?(key: test_key)).to be false
    end

    it "returns false and logs error on S3 service errors" do
      allow(mock_s3_client).to receive(:head_object).and_raise(
        Aws::S3::Errors::ServiceError.new(nil, "Service error")
      )

      expect(Rails.logger).to receive(:error).with(/S3 exists check failed/)
      expect(adapter.exists?(key: test_key)).to be false
    end
  end

  describe "#bucket_name" do
    it "returns the configured bucket name" do
      expect(adapter.bucket_name).to eq(bucket_name)
    end
  end

  describe "#region" do
    it "returns the configured region" do
      expect(adapter.region).to eq(region)
    end
  end
end
