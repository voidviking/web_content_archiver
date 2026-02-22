# frozen_string_literal: true

require "rails_helper"

RSpec.describe Retryable do
  # Use an anonymous class to test the module in isolation
  subject(:retryable_object) do
    Class.new do
      include Retryable

      def call_with_retry(**opts, &block)
        with_retry(**opts, &block)
      end
    end.new
  end

  describe "#with_retry" do
    context "when the block succeeds on the first attempt" do
      it "returns the block result" do
        result = retryable_object.call_with_retry { "success" }
        expect(result).to eq("success")
      end

      it "calls the block exactly once" do
        call_count = 0
        retryable_object.call_with_retry { call_count += 1 }
        expect(call_count).to eq(1)
      end
    end

    context "when the block fails with a transient network error" do
      it "retries up to max_attempts times" do
        call_count = 0
        allow(retryable_object).to receive(:sleep)

        expect {
          retryable_object.call_with_retry(max_attempts: 3) do
            call_count += 1
            raise Net::ReadTimeout
          end
        }.to raise_error(Net::ReadTimeout)

        expect(call_count).to eq(3)
      end

      it "retries on Net::OpenTimeout" do
        call_count = 0
        allow(retryable_object).to receive(:sleep)

        expect {
          retryable_object.call_with_retry(max_attempts: 2) do
            call_count += 1
            raise Net::OpenTimeout
          end
        }.to raise_error(Net::OpenTimeout)

        expect(call_count).to eq(2)
      end

      it "retries on Errno::ECONNRESET" do
        call_count = 0
        allow(retryable_object).to receive(:sleep)

        expect {
          retryable_object.call_with_retry(max_attempts: 2) do
            call_count += 1
            raise Errno::ECONNRESET
          end
        }.to raise_error(Errno::ECONNRESET)

        expect(call_count).to eq(2)
      end

      it "succeeds if a later attempt succeeds" do
        call_count = 0
        allow(retryable_object).to receive(:sleep)

        result = retryable_object.call_with_retry(max_attempts: 3) do
          call_count += 1
          raise Net::ReadTimeout if call_count < 3
          "eventual success"
        end

        expect(result).to eq("eventual success")
        expect(call_count).to eq(3)
      end
    end

    context "exponential backoff" do
      it "sleeps with exponential backoff between retries" do
        allow(retryable_object).to receive(:sleep)
        call_count = 0

        expect {
          retryable_object.call_with_retry(max_attempts: 3, base_delay: 1.0) do
            call_count += 1
            raise Net::ReadTimeout
          end
        }.to raise_error(Net::ReadTimeout)

        expect(retryable_object).to have_received(:sleep).with(1.0).ordered
        expect(retryable_object).to have_received(:sleep).with(2.0).ordered
      end

      it "respects custom base_delay" do
        allow(retryable_object).to receive(:sleep)

        expect {
          retryable_object.call_with_retry(max_attempts: 2, base_delay: 0.5) do
            raise Net::ReadTimeout
          end
        }.to raise_error(Net::ReadTimeout)

        expect(retryable_object).to have_received(:sleep).with(0.5)
      end
    end

    context "when the block fails with a non-transient error" do
      it "does not retry on ArgumentError" do
        call_count = 0

        expect {
          retryable_object.call_with_retry(max_attempts: 3) do
            call_count += 1
            raise ArgumentError, "bad argument"
          end
        }.to raise_error(ArgumentError)

        expect(call_count).to eq(1)
      end

      it "does not retry on RuntimeError" do
        call_count = 0

        expect {
          retryable_object.call_with_retry(max_attempts: 3) do
            call_count += 1
            raise RuntimeError, "unexpected error"
          end
        }.to raise_error(RuntimeError)

        expect(call_count).to eq(1)
      end
    end
  end
end
