# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::DhanTokens' do
  let(:operator_token) { 'operator-secret' }
  let(:headers) { { 'Authorization' => "Bearer #{operator_token}" } }
  let(:expiry) { 6.hours.from_now.change(usec: 0) }

  around do |example|
    prior = ENV.fetch('API_OPERATOR_TOKEN', nil)
    ENV['API_OPERATOR_TOKEN'] = operator_token
    example.run
  ensure
    prior ? ENV['API_OPERATOR_TOKEN'] = prior : ENV.delete('API_OPERATOR_TOKEN')
  end

  describe 'GET /api/dhan/token' do
    it 'returns the live token, expiry and client id to a caller holding the operator token' do
      allow(Dhan::TokenManager).to receive(:snapshot).and_return(token: 'live-token', expiry_time: expiry, client_id: '1100')

      get '/api/dhan/token', headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('access_token' => 'live-token', 'expires_at' => expiry.iso8601, 'client_id' => '1100')
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'rejects a missing or wrong operator token' do
      allow(Dhan::TokenManager).to receive(:snapshot).and_return(token: 'live-token', expiry_time: expiry, client_id: '1100')

      get '/api/dhan/token'
      expect(response).to have_http_status(:unauthorized)

      get '/api/dhan/token', headers: { 'Authorization' => 'Bearer nope' }
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('live-token')
    end

    it 'is never open: refuses to serve when no operator token is configured' do
      ENV.delete('API_OPERATOR_TOKEN')

      get '/api/dhan/token'

      expect(response).to have_http_status(:service_unavailable)
    end

    it 'answers 503 when there is no live token, without triggering a refresh' do
      allow(Dhan::TokenManager).to receive(:snapshot).and_return(nil)
      allow(Dhan::TokenManager).to receive(:refresh!)

      get '/api/dhan/token', headers: headers

      expect(response).to have_http_status(:service_unavailable)
      expect(Dhan::TokenManager).not_to have_received(:refresh!)
    end
  end
end
