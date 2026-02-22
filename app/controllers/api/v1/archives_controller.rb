# frozen_string_literal: true

module Api
  module V1
    class ArchivesController < BaseController
      # POST /api/v1/archives
      def create
        existing = Archive.find_by(url: normalized_url)
        return render json: archive_json(existing), status: :ok if existing

        archive = Archive.new(url: params[:url], status: :pending)

        if archive.save
          # Job will be enqueued here in Commit 10 (after distributed locking is added)
          # ArchiveJob.perform_async(archive.id)
          render json: archive_json(archive), status: :created
        else
          render json: { errors: archive.errors.full_messages }, status: :unprocessable_content
        end
      end

      # GET /api/v1/archives/:id
      def show
        archive = Archive.includes(:resources).find(params[:id])
        render json: archive_json(archive, include_resources: true)
      end

      private

      def normalized_url
        return nil if params[:url].blank?

        uri = Addressable::URI.parse(params[:url])
        uri.scheme = uri.scheme&.downcase
        uri.host = uri.host&.downcase
        uri.query_values = uri.query_values&.sort&.to_h
        uri.fragment = nil

        normalized = uri.normalize.to_s
        normalized.end_with?("/") && !normalized.match?(%r{^https?://[^/]+/$}) ? normalized.chomp("/") : normalized
      rescue Addressable::URI::InvalidURIError
        params[:url]
      end

      def archive_json(archive, include_resources: false)
        json = {
          id: archive.id,
          url: archive.url,
          status: archive.status,
          created_at: archive.created_at,
          updated_at: archive.updated_at
        }

        if include_resources
          json[:resources] = archive.resources.map { |r| resource_json(r) }
        end

        json
      end

      def resource_json(resource)
        {
          id: resource.id,
          original_url: resource.original_url,
          storage_url: resource.storage_url,
          resource_type: resource.resource_type,
          content_type: resource.content_type,
          file_size: resource.file_size
        }
      end
    end
  end
end
