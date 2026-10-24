# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::Auth::Strategies::Authority do
  subject(:strategy) { described_class.new }

  let(:authority_url) { "https://authority.example.com/auth/dhan/token" }
  let(:token_val)     { "authority_access_token" }
  let(:expiry_str)    { "2026-03-25T10:00:00Z" }

  before do
    stub_const("ENV", ENV.to_hash.merge(
      "TRADER_API_BASE_URL" => "https://authority.example.com",
      "DHAN_TOKEN_ACCESS_TOKEN" => "bearer_secret"
    ))
  end

  describe "#call" do
    context "when authority server responds with snake_case keys" do
      before do
        stub_request(:get, authority_url)
          .with(headers: { "Authorization" => "Bearer bearer_secret" })
          .to_return(
            status: 200,
            body: JSON.generate("access_token" => token_val, "expires_at" => expiry_str)
          )
      end

      it "returns normalized token hash" do
        result = strategy.call
        expect(result[:access_token]).to eq(token_val)
        expect(result[:expiry_time]).to be_a(Time)
      end
    end

    context "when authority server responds with camelCase keys" do
      before do
        stub_request(:get, authority_url)
          .to_return(
            status: 200,
            body: JSON.generate("accessToken" => token_val, "expiryTime" => expiry_str)
          )
      end

      it "returns normalized token hash" do
        result = strategy.call
        expect(result[:access_token]).to eq(token_val)
      end
    end

    context "when TRADER_API_BASE_URL is blank" do
      before { stub_const("ENV", ENV.to_hash.merge("TRADER_API_BASE_URL" => "")) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/Authority URL invalid/)
      end
    end

    context "when DHAN_TOKEN_ACCESS_TOKEN is blank" do
      before { stub_const("ENV", ENV.to_hash.merge("DHAN_TOKEN_ACCESS_TOKEN" => "")) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/Authority bearer missing/)
      end
    end

    context "when authority server returns non-200" do
      before do
        stub_request(:get, authority_url).to_return(status: 503, body: "Service Unavailable")
      end

      it "raises with status info" do
        expect { strategy.call }.to raise_error(/Authority request failed.*503/)
      end
    end

    context "when response body is missing token keys" do
      before do
        stub_request(:get, authority_url)
          .to_return(status: 200, body: JSON.generate("expires_at" => expiry_str))
      end

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/missing access_token/)
      end
    end

    context "when TRADER_API_BASE_URL contains template placeholders" do
      before { stub_const("ENV", ENV.to_hash.merge("TRADER_API_BASE_URL" => "<replace-me>")) }

      it "raises a descriptive error" do
        expect { strategy.call }.to raise_error(/Authority URL invalid/)
      end
    end
  end
end
