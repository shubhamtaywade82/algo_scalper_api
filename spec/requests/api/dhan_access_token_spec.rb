# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::DhanAccessToken' do
  describe 'GET /api/dhan_access_token' do
    context 'when token exists' do
      before do
        allow(Dhan::TokenManager).to receive(:current_token).and_return('mock-dhan-access-token')
        DhanAccessToken.delete_all
        DhanAccessToken.create!(token: 'mock-dhan-access-token', expiry_time: 1.day.from_now)
      end

      it 'returns the token and metadata' do
        get '/api/dhan_access_token'

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['dhanaccesstoken']).to eq('mock-dhan-access-token')
        expect(body['dhan_access_token']).to eq('mock-dhan-access-token')
        expect(body['expiry_time']).to be_present
      end
    end

    context 'when token is not found/available' do
      before do
        allow(Dhan::TokenManager).to receive(:current_token).and_return(nil)
      end

      it 'returns 404 not found error' do
        get '/api/dhan_access_token'

        expect(response).to have_http_status(:not_found)
        body = response.parsed_body
        expect(body['error']).to eq('token_not_found')
      end
    end
  end
end
