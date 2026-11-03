# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::EquityCurve' do
  describe 'GET /api/equity_curve' do
    it 'compounds daily trade P&L on top of the ledger opening equity and earlier P&L' do
      allow(Ledger::WalletReader).to receive(:account_balance).with('opening_equity').and_return(BigDecimal(100_000))
      create(:position_tracker, :exited, last_pnl_rupees: 500, exited_at: 100.days.ago)
      create(:position_tracker, :exited, last_pnl_rupees: 1_000, exited_at: 2.days.ago)
      create(:position_tracker, :exited, last_pnl_rupees: -400, exited_at: 1.day.ago)

      get '/api/equity_curve'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.pluck('equity')).to eq([101_500.0, 101_100.0])
      expect(response.parsed_body.last['drawdown_pct']).to be < 0
    end
  end
end
