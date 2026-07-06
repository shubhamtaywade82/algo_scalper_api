# frozen_string_literal: true

require "rails_helper"

RSpec.describe "New Frontend TDD API Endpoints" do
  describe "GET /api/holdings" do
    context "when paper trading is enabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
      end

      it "returns mock paper holdings" do
        get "/api/holdings"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["success"]).to be true
        expect(body["holdings"]).to be_an(Array)
        expect(body["holdings"].first["symbol"]).to eq("TATASTEEL")
      end
    end

    context "when live trading is enabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
        mock_holding = double(to_h: {
          trading_symbol: "SBIN",
          total_qty: 50,
          avg_cost_price: 600.0,
          exchange: "NSE"
        })
        allow(DhanHQ::Models::Holding).to receive(:all).and_return([mock_holding])
      end

      it "calls DhanHQ API and serializes live holdings" do
        get "/api/holdings"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["success"]).to be true
        expect(body["holdings"].first["symbol"]).to eq("SBIN")
        expect(body["holdings"].first["quantity"]).to eq(50)
      end
    end
  end

  describe "GET /api/funds" do
    context "when paper trading is enabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
        allow(Ledger::WalletReader).to receive(:snapshot).and_return({
          cash: 100000.0,
          equity: 100000.0,
          mtm: 0.0,
          exposure: 0.0,
          utilized: 0.0
        })
      end

      it "returns paper ledger wallet balances" do
        get "/api/funds"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["cash"]).to eq(100000.0)
        expect(body["margin_used"]).to eq(0.0)
      end
    end

    context "when live trading is enabled" do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
        mock_funds = double(
          available_balance: 50000.0,
          sod_limit: 50000.0,
          collateral_amount: 0.0,
          receiveable_amount: 0.0,
          utilized_amount: 15000.0
        )
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(mock_funds)
      end

      it "returns live funds from DhanHQ" do
        get "/api/funds"
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["cash"]).to eq(50000.0)
        expect(body["margin_used"]).to eq(15000.0)
      end
    end
  end

  describe "GET /api/reports/pnl" do
    it "returns calculated pnl stats" do
      get "/api/reports/pnl"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be true
      expect(body["summary"]).to include(
        "total_trades",
        "winning_trades",
        "losing_trades",
        "win_rate_percent",
        "net_pnl"
      )
    end
  end

  describe "GET /api/logs" do
    it "returns parsed system logs safely" do
      get "/api/logs"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be true
      expect(body["logs"]).to be_an(Array)
    end
  end

  describe "GET /api/scheduler/tasks" do
    it "returns list of tasks from config/recurring.yml" do
      get "/api/scheduler/tasks"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be true
      expect(body["tasks"]).to be_an(Array)
    end
  end
end
