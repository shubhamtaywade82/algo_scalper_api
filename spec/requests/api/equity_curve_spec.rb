# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::EquityCurve' do
  describe 'GET /api/equity_curve' do
    it 'builds the curve from paper-mode rows only, ignoring live-mode rows for the same dates' do
      PaperDailyWallet.create!(trading_date: Date.yesterday, mode: 'paper', closing_cash: BigDecimal('105000.00'))
      PaperDailyWallet.create!(trading_date: Date.yesterday, mode: 'live', closing_cash: BigDecimal('999999.00'))

      get '/api/equity_curve'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first['equity']).to eq(105000.0)
    end
  end
end
