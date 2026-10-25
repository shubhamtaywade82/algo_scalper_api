# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API orders list' do
  describe 'GET /api/orders' do
    it 'returns the 10 most recent position trackers serialized as orders' do
      oldest = create(:position_tracker, order_no: 'ORD000001')
      newest = create(:position_tracker, order_no: 'ORD000002')

      get '/api/orders'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)

      ids = body['orders'].pluck('id')
      expect(ids).to include(newest.id, oldest.id)

      first = body['orders'].first
      expect(first['order_no']).to be_present
      expect(first['symbol']).to eq(newest.symbol)
      expect(first['quantity']).to eq(newest.quantity.to_i)
      expect(first['entry_price']).to eq(newest.entry_price.to_f)
      expect(first['pnl']).to eq(newest.last_pnl_rupees.to_f)
      expect(first['pnl_pct']).to eq(newest.last_pnl_pct.to_f)
      expect(first['segment']).to eq(newest.segment)
      expect(first['created_at']).to be_present
    end

    it 'caps the result at 10 orders, newest first' do
      older_batch = create_list(:position_tracker, 10)
      newest = create(:position_tracker)

      get '/api/orders'

      body = response.parsed_body
      expect(body['orders'].length).to eq(10)
      # Newest first; the single oldest tracker from the batch falls off the end.
      expected_ids = [newest.id] + older_batch.last(9).reverse.map(&:id)
      expect(body['orders'].pluck('id')).to eq(expected_ids)
    end

    it 'returns an empty list when there are no trackers' do
      get '/api/orders'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['orders']).to eq([])
    end
  end

  describe 'authentication' do
    around do |example|
      previous = ENV.fetch('API_DASHBOARD_TOKEN', nil)
      ENV['API_DASHBOARD_TOKEN'] = 'dash-secret'
      example.run
    ensure
      if previous
        ENV['API_DASHBOARD_TOKEN'] = previous
      else
        ENV.delete('API_DASHBOARD_TOKEN')
      end
    end

    it 'returns 401 without a token' do
      get '/api/orders'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with a matching Bearer token' do
      get '/api/orders', headers: { 'Authorization' => 'Bearer dash-secret' }
      expect(response).to have_http_status(:ok)
    end
  end
end
