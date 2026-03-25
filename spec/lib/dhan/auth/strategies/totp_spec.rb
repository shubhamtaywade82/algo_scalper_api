# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::Strategies::Totp do
  subject(:strategy) { described_class.new }

  let(:expiry_str) { "2026-03-25T10:00:00+05:30" }
  let(:token_val)  { "totp_access_token_xyz" }

  before do
    stub_const("ENV", ENV.to_hash.merge(
      "DHAN_CLIENT_ID" => "client123",
      "DHAN_PIN" => "1234",
      "DHAN_TOTP_SECRET" => "JBSWY3DPEHPK3PXP" # valid base32 secret
    ))
  end

  describe "#call" do
    context "when Dhan auth endpoint returns success" do
      before do
        stub_request(:post, /#{Regexp.escape(described_class::URL)}/o)
          .to_return(
            status: 200,
            body: JSON.generate("accessToken" => token_val, "expiryTime" => expiry_str),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns normalized token hash" do
        result = strategy.call
        expect(result[:access_token]).to eq(token_val)
        expect(result[:expiry_time]).to be_a(Time)
      end
    end

    context "when endpoint returns non-200" do
      before do
        stub_request(:post, /#{Regexp.escape(described_class::URL)}/o).to_return(status: 401, body: "Unauthorized")
      end

      it "raises with status info" do
        expect { strategy.call }.to raise_error(/TOTP auth failed.*401/)
      end
    end

    context "when response body omits token but includes expiry" do
      before do
        stub_request(:post, /#{Regexp.escape(described_class::URL)}/o)
          .to_return(status: 200, body: JSON.generate("expiryTime" => expiry_str))
      end

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/missing access token/)
      end
    end

    context "when Dhan returns HTTP 200 with status error (e.g. invalid TOTP)" do
      before do
        stub_request(:post, /#{Regexp.escape(described_class::URL)}/o)
          .to_return(
            status: 200,
            body: JSON.generate("message" => "Invalid TOTP", "status" => "error"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises with the API message" do
        expect { strategy.call }.to raise_error(/TOTP auth rejected: Invalid TOTP/)
      end
    end

    context "when Dhan returns snake_case success keys" do
      before do
        stub_request(:post, /#{Regexp.escape(described_class::URL)}/o)
          .to_return(
            status: 200,
            body: JSON.generate(
              "access_token" => token_val,
              "expires_at" => expiry_str
            ),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns normalized token hash" do
        result = strategy.call
        expect(result[:access_token]).to eq(token_val)
        expect(result[:expiry_time]).to be_a(Time)
      end
    end

    context "when neither DHAN_CLIENT_ID nor CLIENT_ID is set" do
      before do
        stub_const("ENV", ENV.to_hash.except("DHAN_CLIENT_ID", "CLIENT_ID").merge(
          "DHAN_PIN" => "1234", "DHAN_TOTP_SECRET" => "JBSWY3DPEHPK3PXP"
        ))
      end

      it "raises KeyError" do
        expect { strategy.call }.to raise_error(KeyError)
      end
    end
  end
end
