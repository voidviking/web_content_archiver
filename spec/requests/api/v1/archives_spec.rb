# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Archives", type: :request do
  let(:valid_url) { "https://example.com/page" }
  let(:json_response) { JSON.parse(response.body) }

  describe "POST /api/v1/archives" do
    context "with a valid URL" do
      it "returns 201 Created" do
        post "/api/v1/archives", params: { url: valid_url }

        expect(response).to have_http_status(:created)
      end

      it "creates a new archive record" do
        expect {
          post "/api/v1/archives", params: { url: valid_url }
        }.to change(Archive, :count).by(1)
      end

      it "returns the archive with pending status" do
        post "/api/v1/archives", params: { url: valid_url }

        expect(json_response["status"]).to eq("pending")
      end

      it "returns the expected JSON fields" do
        post "/api/v1/archives", params: { url: valid_url }

        expect(json_response.keys).to include("id", "url", "status", "created_at", "updated_at")
      end

      it "returns the normalized URL" do
        post "/api/v1/archives", params: { url: "HTTPS://EXAMPLE.COM/page" }

        expect(json_response["url"]).to eq("https://example.com/page")
      end
    end

    context "with a duplicate URL" do
      let!(:existing_archive) { create(:archive, url: valid_url, status: :pending) }

      it "returns 200 OK" do
        post "/api/v1/archives", params: { url: valid_url }

        expect(response).to have_http_status(:ok)
      end

      it "does not create a new archive record" do
        expect {
          post "/api/v1/archives", params: { url: valid_url }
        }.not_to change(Archive, :count)
      end

      it "returns the existing archive" do
        post "/api/v1/archives", params: { url: valid_url }

        expect(json_response["id"]).to eq(existing_archive.id)
      end

      it "returns the existing archive status when processing" do
        existing_archive.update!(status: :processing)
        post "/api/v1/archives", params: { url: valid_url }

        expect(json_response["status"]).to eq("processing")
      end

      it "returns the existing archive when already completed" do
        existing_archive.update!(status: :completed)
        post "/api/v1/archives", params: { url: valid_url }

        expect(json_response["status"]).to eq("completed")
      end
    end

    context "with a missing URL" do
      it "returns 422 Unprocessable Entity" do
        post "/api/v1/archives", params: {}

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns error messages" do
        post "/api/v1/archives", params: {}

        expect(json_response["errors"]).to be_present
      end
    end

    context "with an invalid URL format" do
      it "returns 422 for a plain string" do
        post "/api/v1/archives", params: { url: "not-a-url" }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 for a non-http scheme" do
        post "/api/v1/archives", params: { url: "ftp://example.com" }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns descriptive error messages" do
        post "/api/v1/archives", params: { url: "not-a-url" }

        expect(json_response["errors"]).to include(match(/valid HTTP or HTTPS URL/))
      end
    end
  end

  describe "GET /api/v1/archives/:id" do
    context "with an existing archive" do
      let!(:archive) { create(:archive, url: valid_url, status: :pending) }

      it "returns 200 OK" do
        get "/api/v1/archives/#{archive.id}"

        expect(response).to have_http_status(:ok)
      end

      it "returns the expected JSON fields" do
        get "/api/v1/archives/#{archive.id}"

        expect(json_response.keys).to include("id", "url", "status", "resources", "created_at", "updated_at")
      end

      it "returns the correct archive" do
        get "/api/v1/archives/#{archive.id}"

        expect(json_response["id"]).to eq(archive.id)
        expect(json_response["url"]).to eq(archive.url)
        expect(json_response["status"]).to eq("pending")
      end

      it "returns an empty resources array when no resources exist" do
        get "/api/v1/archives/#{archive.id}"

        expect(json_response["resources"]).to eq([])
      end
    end

    context "with a completed archive that has resources" do
      let!(:archive) { create(:archive, :completed) }
      let!(:stylesheet) { create(:resource, :stylesheet, archive: archive) }
      let!(:image) { create(:resource, :image, archive: archive) }

      it "includes all associated resources" do
        get "/api/v1/archives/#{archive.id}"

        expect(json_response["resources"].length).to eq(2)
      end

      it "returns the correct resource fields" do
        get "/api/v1/archives/#{archive.id}"

        resource = json_response["resources"].first
        expect(resource.keys).to include(
          "id", "original_url", "storage_url", "resource_type", "content_type", "file_size"
        )
      end

      it "returns resources with correct types" do
        get "/api/v1/archives/#{archive.id}"

        types = json_response["resources"].map { |r| r["resource_type"] }
        expect(types).to contain_exactly("stylesheet", "image")
      end
    end

    context "with a non-existent archive" do
      it "returns 404 Not Found" do
        get "/api/v1/archives/99999"

        expect(response).to have_http_status(:not_found)
      end

      it "returns an error message" do
        get "/api/v1/archives/99999"

        expect(json_response["error"]).to eq("Resource not found")
      end
    end
  end
end
