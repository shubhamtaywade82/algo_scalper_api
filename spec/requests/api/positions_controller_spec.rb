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
    expect(response.parsed_body.keys).to contain_exactly('error', 'message')
  end

  it 'returns 200 when date is omitted (defaults to today)' do
    get '/api/positions'

    expect(response).to have_http_status(:ok)
  end

  describe 'POST /api/positions/:id/close' do
    it 'delegates to ManualCloseService and returns its status' do
      payload = { status: :ok, json: { success: true, reason: 'MANUAL_DASHBOARD_CLOSE' } }
      allow(Positions::ManualCloseService).to receive(:call).and_return(payload)

      post "/api/positions/42/close"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['success']).to be(true)
      expect(Positions::ManualCloseService).to have_received(:call).with(tracker_id: '42')
    end
  end

  describe 'GET /api/positions/:id' do
    it 'returns the serialized detail for an existing tracker' do
      tracker = create(:position_tracker, segment: 'NSE_FNO')
      allow(Positions::Serializer).to receive(:detail).and_call_original

      get "/api/positions/#{tracker.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(tracker.id)
      expect(Positions::Serializer).to have_received(:detail).with(tracker)
    end

    it 'returns 404 for an unknown id' do
      get '/api/positions/999999'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('not_found')
    end
  end
end
