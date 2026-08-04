# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PositionsController do
  before do
    allow(PositionTracker).to receive_messages(
      active: PositionTracker.none,
      exited: PositionTracker.none,
      paper_trading_stats_with_pct: {}
    )
  end

  it 'returns 422 when date param is not parseable' do
    get '/api/positions', params: { date: '99/99/99' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('invalid_date')
  end

  it 'returns 200 when date is omitted (defaults to today)' do
    get '/api/positions'

    expect(response).to have_http_status(:ok)
  end
end
