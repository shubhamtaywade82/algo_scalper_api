# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::MarketController' do
  describe 'GET /api/market/vix' do
    before do
      allow(Market::VixGate).to receive_messages(
        current_ltp: 14.25,
        evaluated?: true,
        entry_allowed?: true,
        force_exit_active?: false
      )
    end

    it 'returns vix snapshot json' do
      get '/api/market/vix'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['vix']).to eq(14.25)
      expect(body['evaluated']).to be(true)
      expect(body['entry_allowed']).to be(true)
    end
  end
end
