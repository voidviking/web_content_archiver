# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storage::Base do
  subject(:adapter) { described_class.new }

  describe "#upload" do
    it "raises NotImplementedError" do
      expect {
        adapter.upload(key: "test", body: "content", content_type: "text/plain")
      }.to raise_error(NotImplementedError, /must implement #upload/)
    end
  end

  describe "#url_for" do
    it "raises NotImplementedError" do
      expect {
        adapter.url_for(key: "test")
      }.to raise_error(NotImplementedError, /must implement #url_for/)
    end
  end

  describe "#exists?" do
    it "raises NotImplementedError" do
      expect {
        adapter.exists?(key: "test")
      }.to raise_error(NotImplementedError, /must implement #exists\?/)
    end
  end
end
