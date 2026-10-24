# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Strategies::Health' do
  describe 'GET /api/strategies/health/backtest' do
    it 'returns 200 without referencing a nonexistent BacktestRun model' do
      get '/api/strategies/health/backtest'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be true
      expect(body['backtests']).to have_key('available')
      expect(body['backtests']).not_to have_key('jobs')
    end
  end
end
