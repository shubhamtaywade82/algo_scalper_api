# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::Strategies::Renew do
  subject(:strategy) { described_class.new }

  let(:expiry_str) { "2026-03-25T10:00:00+05:30" }
  let(:token_val)  { "renewed_access_token" }
  let(:existing_token) { instance_double(DhanAccessToken, token: "old_token_xyz") }

  before do
    stub_const("ENV", ENV.to_hash.merge("DHAN_CLIENT_ID" => "client123"))
  end

  describe "#call" do
    context "when a valid token exists and renewal succeeds" do
      before do
        allow(DhanAccessToken).to receive(:first).and_return(existing_token)
        stub_request(:post, described_class::URL)
          .with(headers: { "access-token" => "old_token_xyz", "dhanClientId" => "client123" })
          .to_return(
            status: 200,
            body: JSON.generate("accessToken" => token_val, "expiryTime" => expiry_str)
          )
      end

      it "returns normalized token hash" do
        result = strategy.call
        expect(result[:access_token]).to eq(token_val)
        expect(result[:expiry_time]).to be_a(Time)
      end
    end

    context "when no existing token exists" do
      before { allow(DhanAccessToken).to receive(:first).and_return(nil) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/No existing token to renew/)
      end
    end

    context "when renewal endpoint returns failure" do
      before do
        allow(DhanAccessToken).to receive(:first).and_return(existing_token)
        stub_request(:post, described_class::URL).to_return(status: 401, body: "Unauthorized")
      end

      it "raises with status info" do
        expect { strategy.call }.to raise_error(/Renew failed.*401/)
      end
    end

    context "when DHAN_CLIENT_ID is missing" do
      before do
        stub_const("ENV", ENV.to_hash.except("DHAN_CLIENT_ID"))
        allow(DhanAccessToken).to receive(:first).and_return(existing_token)
      end

      it "raises KeyError" do
        expect { strategy.call }.to raise_error(KeyError)
      end
    end
  end
end
