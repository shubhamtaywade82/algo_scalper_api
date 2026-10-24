# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Reports' do
  describe 'GET /api/reports/pnl' do
    it 'reports the real summed per-trade charges, not a flat per-trade placeholder' do
      create(:position_tracker, :exited, charges_rupees: BigDecimal('59.637'))
      create(:position_tracker, :exited, charges_rupees: BigDecimal('40.123'))

      get '/api/reports/pnl'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['summary']['total_brokerage']).to be_within(0.001).of(99.76)
    end

    it 'ignores exited trades with no charges recorded yet (pre-migration data) rather than erroring' do
      create(:position_tracker, :exited, charges_rupees: nil)

      get '/api/reports/pnl'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['summary']['total_brokerage']).to eq(0.0)
    end
  end
end
