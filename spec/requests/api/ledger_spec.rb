# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Ledger' do
  before do
    Ledger::Seeder.seed_accounts!
    Ledger::Seeder.seed_opening_balance!
  end

  describe 'GET /api/ledger/balance' do
    it 'returns wallet and account balances' do
      get '/api/ledger/balance'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['wallet']).to include('cash', 'equity')
      expect(body['accounts']).not_to be_empty
    end
  end

  describe 'GET /api/ledger/journal' do
    it 'returns journal entries' do
      get '/api/ledger/journal'

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['entries']).to be_an(Array)
    end
  end
end
