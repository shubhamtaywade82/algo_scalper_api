# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::AlphaController do
  describe "GET /api/alpha/status" do
    it "reports enabled true when a strategy has desired_status running" do
      create(:strategy_record, slug: "supertrend_v1", desired_status: "running")
      create(:strategy_record, slug: "vwap-reversal", desired_status: "stopped")

      get "/api/alpha/status"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["enabled"]).to be(true)
      expect(body["strategies"]).to contain_exactly("supertrend_v1", "vwap-reversal")
    end

    it "reports enabled false when no strategy is running" do
      create(:strategy_record, slug: "supertrend_v1", desired_status: "stopped")

      get "/api/alpha/status"

      expect(response.parsed_body["enabled"]).to be(false)
    end
  end

  describe "GET /api/alpha/history" do
    it "serializes strategy signals with strategy slug, direction, and linked position data" do
      strategy = create(:strategy_record, slug: "supertrend_v1")
      version = create(:strategy_version, strategy_record: strategy)
      run = create(:strategy_run, strategy_record: strategy, strategy_version: version)
      instrument = create(:instrument)
      tracker = create(:position_tracker, instrument: instrument, segment: "NSE_FNO",
                                          symbol: "NIFTY26APR23000CE", quantity: 75,
                                          last_pnl_rupees: BigDecimal("1250.5"), atm_strike: 23_000)
      signal = create(:strategy_signal, strategy_record: strategy, strategy_version: version, strategy_run: run,
                                        instrument_key: "NIFTY", action: "buy_call", confidence: 0.8,
                                        outcome: "executed", position_tracker: tracker, emitted_at: Time.current)

      get "/api/alpha/history"

      expect(response).to have_http_status(:ok)
      row = response.parsed_body.find { |r| r["id"] == signal.id }
      expect(row).to include(
        "alpha_source" => "supertrend_v1",
        "index_key" => "NIFTY",
        "direction" => "bullish",
        "confidence" => 0.8,
        "status" => "entered",
        "strike_price" => 23_000.0,
        "pnl" => 1250.5,
        "symbol" => "NIFTY26APR23000CE"
      )
    end

    it "returns nil strike/pnl/symbol for signals with no linked position" do
      strategy = create(:strategy_record, slug: "vwap-reversal")
      version = create(:strategy_version, strategy_record: strategy)
      run = create(:strategy_run, strategy_record: strategy, strategy_version: version)
      signal = create(:strategy_signal, strategy_record: strategy, strategy_version: version, strategy_run: run,
                                        instrument_key: "SENSEX", action: "hold", outcome: "shadow",
                                        emitted_at: Time.current)

      get "/api/alpha/history"

      row = response.parsed_body.find { |r| r["id"] == signal.id }
      expect(row).to include("strike_price" => nil, "pnl" => nil, "symbol" => nil, "status" => "skipped")
    end
  end

  describe "GET /api/alpha/performance" do
    it "groups executed signal pnl by strategy slug" do
      strategy = create(:strategy_record, slug: "supertrend_v1")
      version = create(:strategy_version, strategy_record: strategy)
      run = create(:strategy_run, strategy_record: strategy, strategy_version: version)
      instrument = create(:instrument)
      winning_tracker = create(:position_tracker, instrument: instrument, segment: "NSE_FNO",
                                                  last_pnl_rupees: BigDecimal("500.0"))
      losing_tracker = create(:position_tracker, instrument: instrument, segment: "NSE_FNO",
                                                 last_pnl_rupees: BigDecimal("-200.0"))
      create(:strategy_signal, strategy_record: strategy, strategy_version: version, strategy_run: run,
                               outcome: "executed", position_tracker: winning_tracker, emitted_at: Time.current)
      create(:strategy_signal, strategy_record: strategy, strategy_version: version, strategy_run: run,
                               outcome: "executed", position_tracker: losing_tracker, emitted_at: Time.current)

      get "/api/alpha/performance"

      body = response.parsed_body
      stats = body["by_source"]["supertrend_v1"]
      expect(stats["count"]).to eq(2)
      expect(stats["total_pnl"]).to eq(300.0)
      expect(stats["win_rate"]).to eq(50.0)
      expect(body["total_executed"]).to eq(2)
    end
  end

  describe "removed actions" do
    it "no longer routes POST /api/alpha/scan" do
      post "/api/alpha/scan"

      expect(response).to have_http_status(:not_found)
    end

    it "no longer routes POST /api/alpha/execute" do
      post "/api/alpha/execute"

      expect(response).to have_http_status(:not_found)
    end
  end
end
