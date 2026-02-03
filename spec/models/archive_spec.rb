# frozen_string_literal: true

require "rails_helper"

RSpec.describe Archive, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:resources).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:archive) }

    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_uniqueness_of(:url) }
    it { is_expected.to validate_presence_of(:status) }

    it "validates URL format" do
      archive = build(:archive, url: "invalid-url")
      expect(archive).not_to be_valid
      expect(archive.errors[:url]).to include("must be a valid HTTP or HTTPS URL")
    end

    it "accepts valid HTTP URLs" do
      archive = build(:archive, url: "http://example.com")
      expect(archive).to be_valid
    end

    it "accepts valid HTTPS URLs" do
      archive = build(:archive, url: "https://example.com")
      expect(archive).to be_valid
    end

    it "rejects URLs without http/https scheme" do
      archive = build(:archive, url: "ftp://example.com")
      expect(archive).not_to be_valid
    end

    it "rejects URLs without scheme" do
      archive = build(:archive, url: "example.com")
      expect(archive).not_to be_valid
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(described_class.statuses).to eq({
        "pending" => 0,
        "processing" => 1,
        "completed" => 2,
        "failed" => 3
      })
    end

    it "allows setting status as symbol" do
      archive = create(:archive, status: :pending)
      expect(archive.status).to eq("pending")
      expect(archive.status_pending?).to be true
    end

    it "provides status predicate methods" do
      archive = create(:archive)

      archive.status = :pending
      expect(archive.status_pending?).to be true
      expect(archive.status_processing?).to be false

      archive.status = :processing
      expect(archive.status_processing?).to be true
      expect(archive.status_completed?).to be false

      archive.status = :completed
      expect(archive.status_completed?).to be true
      expect(archive.status_failed?).to be false

      archive.status = :failed
      expect(archive.status_failed?).to be true
    end
  end

  describe "URL normalization" do
    it "normalizes URL before validation" do
      archive = create(:archive, url: "HTTPS://EXAMPLE.COM/Path/")
      expect(archive.url).to eq("https://example.com/Path")
    end

    it "removes trailing slash from path" do
      archive = create(:archive, url: "https://example.com/page/")
      expect(archive.url).to eq("https://example.com/page")
    end

    it "keeps trailing slash for root path" do
      archive = create(:archive, url: "https://example.com/")
      expect(archive.url).to eq("https://example.com/")
    end

    it "sorts query parameters" do
      archive = create(:archive, url: "https://example.com?z=1&a=2&m=3")
      expect(archive.url).to eq("https://example.com/?a=2&m=3&z=1")
    end

    it "removes fragment identifiers" do
      archive = create(:archive, url: "https://example.com/page#section")
      expect(archive.url).to eq("https://example.com/page")
    end

    it "normalizes scheme to lowercase" do
      archive = create(:archive, url: "HTTPS://example.com")
      expect(archive.url).to eq("https://example.com/")
    end

    it "handles URLs with port numbers" do
      archive = create(:archive, url: "https://example.com:8080/page")
      expect(archive.url).to eq("https://example.com:8080/page")
    end

    it "handles complex query parameters" do
      archive = create(:archive, url: "https://example.com?param=value&another=test")
      expect(archive.url).to include("another=test")
      expect(archive.url).to include("param=value")
    end
  end

  describe "database constraints" do
    it "enforces URL uniqueness at database level" do
      create(:archive, url: "https://example.com/unique")

      duplicate_archive = Archive.new(url: "https://example.com/unique", status: :pending)

      expect {
        duplicate_archive.save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "has default lock_version of 0" do
      archive = create(:archive)
      expect(archive.lock_version).to eq(0)
    end

    it "has default status of pending" do
      archive = Archive.create!(url: "https://example.com/test")
      expect(archive.status).to eq("pending")
    end
  end

  describe "optimistic locking" do
    it "increments lock_version on update" do
      archive = create(:archive)
      initial_version = archive.lock_version

      archive.update!(status: :processing)
      expect(archive.lock_version).to eq(initial_version + 1)
    end

    it "raises StaleObjectError on concurrent updates" do
      archive = create(:archive)

      archive1 = Archive.find(archive.id)
      archive2 = Archive.find(archive.id)

      archive1.update!(status: :processing)

      expect {
        archive2.update!(status: :completed)
      }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end

  describe "destroying archive" do
    it "destroys associated resources" do
      archive = create(:archive)
      create_list(:resource, 3, archive: archive)

      expect { archive.destroy }.to change(Resource, :count).by(-3)
    end
  end

  describe "factory" do
    it "creates a valid archive" do
      archive = build(:archive)
      expect(archive).to be_valid
    end

    it "creates archive with traits" do
      pending_archive = build(:archive, :pending)
      expect(pending_archive.status).to eq("pending")

      processing_archive = build(:archive, :processing)
      expect(processing_archive.status).to eq("processing")

      completed_archive = build(:archive, :completed)
      expect(completed_archive.status).to eq("completed")
      expect(completed_archive.content).to be_present

      failed_archive = build(:archive, :failed)
      expect(failed_archive.status).to eq("failed")
      expect(failed_archive.error_message).to be_present
    end
  end
end
