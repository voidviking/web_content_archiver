# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storage::LocalAdapter do
  subject(:adapter) { described_class.new }

  let(:test_key) { "test-file-#{SecureRandom.hex(8)}.txt" }
  let(:test_content) { "Hello, World! #{SecureRandom.hex(8)}" }
  let(:content_type) { "text/plain" }

  after do
    # Clean up test files
    file_path = adapter.file_path(key: test_key)
    File.delete(file_path) if File.exist?(file_path)
  end

  describe "#upload" do
    it "uploads content to local filesystem" do
      result = adapter.upload(key: test_key, body: test_content, content_type: content_type)

      expect(result).to eq(test_key)
      expect(adapter.exists?(key: test_key)).to be true
    end

    it "creates nested directories if key contains slashes" do
      nested_key = "archived/2024/01/test.txt"
      result = adapter.upload(key: nested_key, body: test_content, content_type: content_type)

      expect(result).to eq(nested_key)
      expect(adapter.exists?(key: nested_key)).to be true

      # Clean up
      File.delete(adapter.file_path(key: nested_key))
    end

    it "handles IO objects as body" do
      io = StringIO.new(test_content)
      result = adapter.upload(key: test_key, body: io, content_type: content_type)

      expect(result).to eq(test_key)
      file_content = File.read(adapter.file_path(key: test_key))
      expect(file_content).to eq(test_content)
    end

    it "overwrites existing files" do
      adapter.upload(key: test_key, body: "original content", content_type: content_type)
      adapter.upload(key: test_key, body: test_content, content_type: content_type)

      file_content = File.read(adapter.file_path(key: test_key))
      expect(file_content).to eq(test_content)
    end
  end

  describe "#url_for" do
    it "returns a relative URL path" do
      url = adapter.url_for(key: test_key)

      expect(url).to eq("/archived_assets/#{test_key}")
    end

    it "handles keys with nested paths" do
      nested_key = "archived/2024/01/test.txt"
      url = adapter.url_for(key: nested_key)

      expect(url).to eq("/archived_assets/#{nested_key}")
    end
  end

  describe "#exists?" do
    it "returns true for existing files" do
      adapter.upload(key: test_key, body: test_content, content_type: content_type)

      expect(adapter.exists?(key: test_key)).to be true
    end

    it "returns false for non-existent files" do
      expect(adapter.exists?(key: "non-existent-file.txt")).to be false
    end
  end

  describe "#file_path" do
    it "returns the absolute path to the file" do
      path = adapter.file_path(key: test_key)

      expect(path).to be_a(Pathname)
      expect(path.to_s).to include("storage/archived_assets")
      expect(path.to_s).to end_with(test_key)
    end
  end

  describe "initialization" do
    it "creates the storage directory if it doesn't exist" do
      storage_path = Rails.root.join("storage", "archived_assets")

      expect(storage_path).to exist
      expect(storage_path).to be_directory
    end
  end
end
