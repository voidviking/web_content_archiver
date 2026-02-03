# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resource, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:archive) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:original_url) }
    it { is_expected.to validate_presence_of(:resource_type) }
  end

  describe "enums" do
    it "defines resource_type enum" do
      expect(described_class.resource_types).to eq({
        "stylesheet" => 0,
        "script" => 1,
        "image" => 2,
        "font" => 3,
        "other" => 4
      })
    end

    it "allows setting resource_type as symbol" do
      resource = create(:resource, resource_type: :stylesheet)
      expect(resource.resource_type).to eq("stylesheet")
      expect(resource.resource_type_stylesheet?).to be true
    end

    it "provides resource_type predicate methods" do
      resource = create(:resource)

      resource.resource_type = :stylesheet
      expect(resource.resource_type_stylesheet?).to be true
      expect(resource.resource_type_script?).to be false

      resource.resource_type = :script
      expect(resource.resource_type_script?).to be true
      expect(resource.resource_type_image?).to be false

      resource.resource_type = :image
      expect(resource.resource_type_image?).to be true
      expect(resource.resource_type_font?).to be false

      resource.resource_type = :font
      expect(resource.resource_type_font?).to be true
      expect(resource.resource_type_other?).to be false

      resource.resource_type = :other
      expect(resource.resource_type_other?).to be true
    end
  end

  describe "database constraints" do
    it "requires an archive" do
      resource = build(:resource, archive: nil)
      expect(resource).not_to be_valid
    end

    it "has default resource_type of stylesheet (0)" do
      archive = create(:archive)
      resource = Resource.create!(
        archive: archive,
        original_url: "https://example.com/style.css"
      )
      expect(resource.resource_type).to eq("stylesheet")
    end

    it "allows multiple resources with same original_url for different archives" do
      archive1 = create(:archive, url: "https://example.com/page1")
      archive2 = create(:archive, url: "https://example.com/page2")
      url = "https://cdn.example.com/shared.css"

      resource1 = create(:resource, archive: archive1, original_url: url)
      resource2 = create(:resource, archive: archive2, original_url: url)

      expect(resource1).to be_valid
      expect(resource2).to be_valid
    end
  end

  describe "factory" do
    it "creates a valid resource" do
      resource = build(:resource)
      expect(resource).to be_valid
    end

    it "creates resource with stylesheet trait" do
      resource = build(:resource, :stylesheet)
      expect(resource.resource_type).to eq("stylesheet")
      expect(resource.content_type).to eq("text/css")
    end

    it "creates resource with script trait" do
      resource = build(:resource, :script)
      expect(resource.resource_type).to eq("script")
      expect(resource.content_type).to eq("application/javascript")
    end

    it "creates resource with image trait" do
      resource = build(:resource, :image)
      expect(resource.resource_type).to eq("image")
      expect(resource.content_type).to eq("image/png")
    end

    it "creates resource with font trait" do
      resource = build(:resource, :font)
      expect(resource.resource_type).to eq("font")
      expect(resource.content_type).to eq("font/woff2")
    end

    it "creates resource with other trait" do
      resource = build(:resource, :other)
      expect(resource.resource_type).to eq("other")
      expect(resource.content_type).to eq("application/octet-stream")
    end
  end

  describe "association cascade" do
    it "is destroyed when archive is destroyed" do
      archive = create(:archive)
      resource = create(:resource, archive: archive)

      expect { archive.destroy }.to change(Resource, :count).by(-1)
      expect(Resource.exists?(resource.id)).to be false
    end
  end

  describe "storage fields" do
    it "can store storage_key and storage_url" do
      resource = create(:resource,
        storage_key: "assets/abc123/style.css",
        storage_url: "https://s3.amazonaws.com/bucket/assets/abc123/style.css"
      )

      expect(resource.storage_key).to eq("assets/abc123/style.css")
      expect(resource.storage_url).to eq("https://s3.amazonaws.com/bucket/assets/abc123/style.css")
    end

    it "can store file_size" do
      resource = create(:resource, file_size: 2048)
      expect(resource.file_size).to eq(2048)
    end

    it "can store content_type" do
      resource = create(:resource, content_type: "image/jpeg")
      expect(resource.content_type).to eq("image/jpeg")
    end
  end
end
