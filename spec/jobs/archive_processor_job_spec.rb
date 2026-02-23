# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArchiveProcessorJob, type: :job do
  subject(:job) { described_class.new }

  let(:archive) { create(:archive, :pending, url: "https://example.com/page") }

  let(:html_body) { "<html><head><link rel='stylesheet' href='https://example.com/style.css'></head><body><img src='https://example.com/logo.png'></body></html>" }
  let(:rewritten_html) { "<html><head><link rel='stylesheet' href='/storage/style.css'></head><body><img src='/storage/logo.png'></body></html>" }

  let(:css_resource)  { { url: "https://example.com/style.css", type: :stylesheet } }
  let(:img_resource)  { { url: "https://example.com/logo.png",  type: :image } }
  let(:extracted_resources) { [ css_resource, img_resource ] }

  let(:css_fetched) { { url: css_resource[:url], type: :stylesheet, result: { body: "body{}", content_type: "text/css",  size: 6 } } }
  let(:img_fetched) { { url: img_resource[:url], type: :image,      result: { body: "\x89PNG".b, content_type: "image/png", size: 4 } } }
  let(:fetched_resources) { [ css_fetched, img_fetched ] }

  let(:storage) { instance_double(Storage::LocalAdapter) }

  before do
    allow(HtmlFetcher).to receive(:call).with(archive.url).and_return(
      { body: html_body, content_type: "text/html", final_url: archive.url }
    )
    allow(ResourceExtractor).to receive(:call).with(html_body, base_url: archive.url).and_return(extracted_resources)
    allow(ParallelResourceFetcher).to receive(:call).with(extracted_resources).and_return(fetched_resources)
    allow(UrlRewriter).to receive(:call).with(html_body, instance_of(Hash)).and_return(rewritten_html)

    allow(Storage::AdapterFactory).to receive(:build).and_return(storage)
    allow(storage).to receive(:upload)
    allow(storage).to receive(:url_for).with(key: /archives\/#{archive.id}\/.*\.css/).and_return("/storage/style.css")
    allow(storage).to receive(:url_for).with(key: /archives\/#{archive.id}\/.*\.png/).and_return("/storage/logo.png")
  end

  describe "#perform" do
    context "happy path" do
      it "transitions the archive from pending → processing → completed" do
        expect { job.perform(archive.id) }
          .to change { archive.reload.status }.from("pending").to("completed")
      end

      it "stores the rewritten HTML in the archive content field" do
        job.perform(archive.id)
        expect(archive.reload.content).to eq(rewritten_html)
      end

      it "creates a Resource record for each successfully fetched asset" do
        expect { job.perform(archive.id) }.to change(Resource, :count).by(2)
      end

      it "persists the correct original_url for each resource" do
        job.perform(archive.id)
        original_urls = archive.reload.resources.pluck(:original_url)
        expect(original_urls).to contain_exactly(css_resource[:url], img_resource[:url])
      end

      it "persists the correct resource_type for each resource" do
        job.perform(archive.id)
        types = archive.reload.resources.pluck(:resource_type)
        expect(types).to contain_exactly("stylesheet", "image")
      end

      it "persists the storage_url returned by the adapter" do
        job.perform(archive.id)
        storage_urls = archive.reload.resources.pluck(:storage_url)
        expect(storage_urls).to contain_exactly("/storage/style.css", "/storage/logo.png")
      end

      it "uploads each asset to storage once" do
        job.perform(archive.id)
        expect(storage).to have_received(:upload).exactly(fetched_resources.size).times
      end

      it "passes the correct content_type to storage upload for CSS" do
        job.perform(archive.id)
        expect(storage).to have_received(:upload).with(hash_including(content_type: "text/css"))
      end

      it "passes the correct content_type to storage upload for images" do
        job.perform(archive.id)
        expect(storage).to have_received(:upload).with(hash_including(content_type: "image/png"))
      end

      it "calls UrlRewriter with a mapping of original → storage URLs" do
        job.perform(archive.id)
        expect(UrlRewriter).to have_received(:call).with(
          html_body,
          hash_including(
            css_resource[:url] => "/storage/style.css",
            img_resource[:url] => "/storage/logo.png"
          )
        )
      end
    end

    context "when the archive is already completed" do
      let(:archive) { create(:archive, :completed) }

      it "does nothing and returns early" do
        job.perform(archive.id)
        expect(HtmlFetcher).not_to have_received(:call)
      end

      it "leaves the archive as completed" do
        expect { job.perform(archive.id) }.not_to change { archive.reload.status }
      end
    end

    context "when another worker already claimed the archive (status: processing)" do
      let(:archive) { create(:archive, :processing) }

      it "does not fetch the page" do
        job.perform(archive.id)
        expect(HtmlFetcher).not_to have_received(:call)
      end

      it "leaves the archive as processing" do
        expect { job.perform(archive.id) }.not_to change { archive.reload.status }
      end
    end

    context "when some assets fail to fetch" do
      let(:img_fetched_nil) { { url: img_resource[:url], type: :image, result: nil } }
      let(:fetched_resources) { [ css_fetched, img_fetched_nil ] }

      it "only creates Resource records for successful fetches" do
        expect { job.perform(archive.id) }.to change(Resource, :count).by(1)
      end

      it "still completes the archive" do
        job.perform(archive.id)
        expect(archive.reload.status).to eq("completed")
      end
    end

    context "when HtmlFetcher raises" do
      before do
        allow(HtmlFetcher).to receive(:call).and_raise(HtmlFetcher::FetchError.new("connection refused", status_code: 503))
      end

      it "marks the archive as failed" do
        job.perform(archive.id) rescue nil
        expect(archive.reload.status).to eq("failed")
      end

      it "persists the error message" do
        job.perform(archive.id) rescue nil
        expect(archive.reload.error_message).to include("connection refused")
      end

      it "re-raises so Sidekiq can apply its retry policy" do
        expect { job.perform(archive.id) }.to raise_error(HtmlFetcher::FetchError)
      end

      it "does not create any Resource records" do
        job.perform(archive.id) rescue nil
        expect(Resource.count).to eq(0)
      end
    end

    context "when the archive record does not exist" do
      it "is discarded without raising" do
        # discard_on only fires through the ActiveJob middleware stack,
        # so we use perform_now (not job.perform) to exercise that path.
        expect { described_class.perform_now(0) }.not_to raise_error
      end
    end

    context "storage key generation" do
      it "generates unique storage keys per asset" do
        job.perform(archive.id)
        keys = archive.reload.resources.pluck(:storage_key)
        expect(keys.uniq.size).to eq(keys.size)
      end

      it "scopes storage keys under the archive id" do
        job.perform(archive.id)
        archive.reload.resources.each do |resource|
          expect(resource.storage_key).to start_with("archives/#{archive.id}/")
        end
      end
    end
  end
end
