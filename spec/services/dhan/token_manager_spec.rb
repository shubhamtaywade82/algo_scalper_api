# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dhan::TokenManager do
  let(:strategy_double) { instance_double(Dhan::Auth::Strategies::Base) }
  let(:future_expiry)   { 2.hours.from_now }
  let(:fresh_response)  { { access_token: "fresh_token", expiry_time: future_expiry } }

  before do
    described_class.instance_variable_set(:@cached_token, nil)
    described_class.instance_variable_set(:@mutex, nil)

    allow(Dhan::Auth::StrategyResolver).to receive(:resolve).and_return(strategy_double)
    allow(DhanHQ).to receive(:configure)
    allow(ENV).to receive(:[]=)
    # Prevent WebSocket restart in specs
    allow(described_class).to receive(:restart_websocket!)
  end

  describe ".current_token!" do
    context "when token exists and is not expiring" do
      before do
        DhanAccessToken.create!(token: "cached_token", expiry_time: 2.hours.from_now)
      end

      it "returns cached token without calling the strategy" do
        expect(described_class.current_token!).to eq("cached_token")
        expect(Dhan::Auth::StrategyResolver).not_to have_received(:resolve)
      end
    end

    context "when no token in DB" do
      before do
        allow(strategy_double).to receive(:call).and_return(fresh_response)
      end

      it "calls the strategy and returns the new token" do
        expect(described_class.current_token!).to eq("fresh_token")
      end
    end

    context "when token is expiring soon (within buffer)" do
      before do
        DhanAccessToken.create!(token: "expiring_token", expiry_time: 10.minutes.from_now)
        allow(strategy_double).to receive(:call).and_return(fresh_response)
      end

      it "refreshes and returns the new token" do
        expect(described_class.current_token!).to eq("fresh_token")
        expect(Dhan::Auth::StrategyResolver).to have_received(:resolve)
      end
    end

    context "when strategy raises an error" do
      before { allow(strategy_double).to receive(:call).and_raise(RuntimeError, "auth failed") }

      it "returns nil without raising" do
        expect(described_class.current_token!).to be_nil
      end
    end
  end

  describe ".refresh!" do
    context "with force: true" do
      before { allow(strategy_double).to receive(:call).and_return(fresh_response) }

      it "always calls the strategy regardless of cached state" do
        DhanAccessToken.create!(token: "old_token", expiry_time: 2.hours.from_now)
        described_class.instance_variable_set(:@cached_token, { token: "old_token", expiry_time: 2.hours.from_now })

        token = described_class.refresh!(force: true)
        expect(token).to eq("fresh_token")
        expect(strategy_double).to have_received(:call)
      end
    end

    context "when strategy succeeds" do
      before { allow(strategy_double).to receive(:call).and_return(fresh_response) }

      it "persists the token to the DB" do
        described_class.refresh!(force: true)
        record = DhanAccessToken.first
        expect(record&.token).to eq("fresh_token")
      end

      it "updates the in-memory cache" do
        described_class.refresh!(force: true)
        cached = described_class.instance_variable_get(:@cached_token)
        expect(cached[:token]).to eq("fresh_token")
      end

      it "returns the access token string" do
        expect(described_class.refresh!(force: true)).to eq("fresh_token")
      end
    end

    context "when strategy raises" do
      before { allow(strategy_double).to receive(:call).and_raise(RuntimeError, "network error") }

      it "returns nil" do
        expect(described_class.refresh!(force: true)).to be_nil
      end

      it "logs the error" do
        allow(Rails.logger).to receive(:error)
        described_class.refresh!(force: true)
        expect(Rails.logger).to have_received(:error).with(/Token refresh failed/)
      end
    end
  end

  describe ".clear_cache!" do
    before do
      DhanAccessToken.create!(token: "some_token", expiry_time: 1.hour.from_now)
      described_class.instance_variable_set(:@cached_token, { token: "some_token", expiry_time: 1.hour.from_now })
    end

    it "clears the in-memory cache" do
      described_class.clear_cache!
      expect(described_class.instance_variable_get(:@cached_token)).to be_nil
    end

    it "deletes all DB records" do
      described_class.clear_cache!
      expect(DhanAccessToken.count).to eq(0)
    end

    it "returns true" do
      expect(described_class.clear_cache!).to be true
    end
  end
end
