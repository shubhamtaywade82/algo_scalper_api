# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::Research::SignalsController do
  describe "GET /api/research/signals" do
    it "lists signals newest first with pagination meta" do
      Research::Signal.create!(underlying_symbol: "NIFTY", signal_timestamp: 2.hours.ago, direction: "bullish",
                                spot_price: 24_800)
      newest = Research::Signal.create!(underlying_symbol: "NIFTY", signal_timestamp: 1.hour.ago,
                                         direction: "bearish", spot_price: 24_900)

      get "/api/research/signals"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["signals"].first["id"]).to eq(newest.id)
      expect(body["meta"]).to include("total" => 2, "page" => 1)
    end

    it "filters by underlying_symbol" do
      Research::Signal.create!(underlying_symbol: "NIFTY", signal_timestamp: 1.hour.ago, direction: "bullish",
                                spot_price: 24_800)
      Research::Signal.create!(underlying_symbol: "SENSEX", signal_timestamp: 1.hour.ago, direction: "bullish",
                                spot_price: 81_000)

      get "/api/research/signals", params: { underlying_symbol: "sensex" }

      body = response.parsed_body
      expect(body["signals"].size).to eq(1)
      expect(body["signals"].first["underlying_symbol"]).to eq("SENSEX")
    end
  end

  describe "GET /api/research/signals/:id" do
    it "returns the signal with its candidates" do
      signal = Research::Signal.create!(underlying_symbol: "NIFTY", signal_timestamp: 1.hour.ago,
                                         direction: "bullish", spot_price: 24_800)
      Research::OptionCandidate.create!(research_signal: signal, underlying_symbol: "NIFTY", expiry_flag: "WEEK",
                                        option_type: "CE", strike_label: "ATM", strike_distance: 0,
                                        actual_strike: 24_800, entry_model: "next_candle_open", status: "scored",
                                        return_pct: 12.5)

      get "/api/research/signals/#{signal.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["signal"]["id"]).to eq(signal.id)
      expect(body["candidates"].size).to eq(1)
      expect(body["candidates"].first["return_pct"]).to eq(12.5)
    end

    it "returns 404 for an unknown id" do
      get "/api/research/signals/999999"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/research/signals" do
    it "builds a signal and runs the pipeline, returning ranked candidates" do
      allow(Research::Pipeline).to receive(:run) do |signal:, **|
        [Research::OptionCandidate.create!(research_signal: signal, underlying_symbol: signal.underlying_symbol,
                                            expiry_flag: "WEEK", option_type: "CE", strike_label: "ATM",
                                            strike_distance: 0, actual_strike: 24_800, status: "scored",
                                            return_pct: 30.0)]
      end

      post "/api/research/signals", params: {
        underlying_symbol: "NIFTY", signal_timestamp: "2026-07-10 10:14:00", direction: "bullish",
        spot_price: 24_800, expiry_flag: "WEEK", max_distance: 1
      }

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["signal"]["underlying_symbol"]).to eq("NIFTY")
      expect(body["candidates"].first["return_pct"]).to eq(30.0)
      expect(Research::Pipeline).to have_received(:run)
    end

    it "returns 422 when a required param is missing" do
      post "/api/research/signals", params: { underlying_symbol: "NIFTY" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
