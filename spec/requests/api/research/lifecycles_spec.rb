# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::Research::LifecyclesController do
  describe "GET /api/research/lifecycles" do
    it "lists lifecycles newest first, filterable by symbol/expiry_flag/option_type/date" do
      Research::PremiumLifecycle.create!(underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "CE",
                                          strike_label: "ATM", interval: "5", entry_ts: 2.days.ago, status: "computed",
                                          peak_return_pct: 40.0)
      newest = Research::PremiumLifecycle.create!(underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "PE",
                                                    strike_label: "ATM", interval: "5", entry_ts: 1.day.ago,
                                                    status: "computed", peak_return_pct: 10.0)

      get "/api/research/lifecycles", params: { underlying_symbol: "nifty", option_type: "PE" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["lifecycles"].size).to eq(1)
      expect(body["lifecycles"].first["id"]).to eq(newest.id)
    end
  end

  describe "GET /api/research/lifecycles/:id" do
    it "returns the lifecycle with its option bars for charting" do
      lifecycle = Research::PremiumLifecycle.create!(
        underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "CE", strike_label: "ATM", interval: "5",
        entry_ts: Time.zone.parse("2026-07-10 09:15:00"), end_ts: Time.zone.parse("2026-07-10 09:25:00"),
        status: "computed", peak_return_pct: 40.0
      )
      Research::OptionBar.create!(underlying_symbol: "NIFTY", exchange_segment: "NSE_FNO", expiry_flag: "WEEK",
                                   option_type: "CE", strike_label: "ATM", interval: "5",
                                   ts: Time.zone.parse("2026-07-10 09:15:00"), open: 100, high: 105, low: 98,
                                   close: 101)

      get "/api/research/lifecycles/#{lifecycle.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["lifecycle"]["id"]).to eq(lifecycle.id)
      expect(body["bars"].size).to eq(1)
      expect(body["bars"].first["close"]).to eq(101.0)
    end
  end

  describe "POST /api/research/lifecycles/run" do
    it "runs the lifecycle board and returns ranked results" do
      allow(Research::LifecycleRunner).to receive(:run).and_return(
        [Research::PremiumLifecycle.create!(underlying_symbol: "NIFTY", expiry_flag: "WEEK", option_type: "CE",
                                             strike_label: "ATM", interval: "5", entry_ts: Time.current,
                                             status: "computed", peak_return_pct: 55.0)]
      )

      post "/api/research/lifecycles/run", params: {
        underlying_symbol: "NIFTY", date: "2026-07-10", spot_price: 24_800, expiry_flag: "WEEK", max_distance: 2
      }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["lifecycles"].first["peak_return_pct"]).to eq(55.0)
      expect(Research::LifecycleRunner).to have_received(:run)
    end

    it "returns 422 for an invalid date" do
      post "/api/research/lifecycles/run", params: { underlying_symbol: "NIFTY", date: "not-a-date",
                                                       spot_price: 24_800 }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
