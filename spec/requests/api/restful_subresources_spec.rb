# frozen_string_literal: true

require 'rails_helper'

# Sub-resources split out of former custom actions (funds/add, scheduler execute,
# ledger/position, strategies/health/*). Each must answer on its RESTful path.
RSpec.describe 'RESTful API sub-resources' do # rubocop:disable RSpec/DescribeClass
  describe 'POST /api/funds/deposits and /api/funds/withdrawals' do
    before { allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } }) }

    it 'deposits into and withdraws from the paper wallet' do
      post '/api/funds/deposits', params: { amount: 1000 }, as: :json
      expect(response).to have_http_status(:ok)
      cash_after_deposit = response.parsed_body['cash']

      post '/api/funds/withdrawals', params: { amount: 400 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['cash']).to eq(cash_after_deposit - 400)
    end

    it 'rejects a non-positive amount' do
      post '/api/funds/deposits', params: { amount: 0 }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST /api/scheduler/tasks/:task_id/executions' do
    it 'returns 404 for a task that is not in recurring.yml' do
      post '/api/scheduler/tasks/no_such_task/executions'
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('task_not_found')
    end
  end

  describe 'GET /api/positions/:position_id/journal_entries' do
    it 'returns the ledger entries for the position' do
      tracker = create(:position_tracker)
      get "/api/positions/#{tracker.id}/journal_entries"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('position_tracker_id' => tracker.id, 'entries' => [])
    end

    it 'returns 404 for an unknown position' do
      get '/api/positions/999999/journal_entries'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/strategies/health/{pool,session}' do
    it 'reports the runner pool and trading session' do
      get '/api/strategies/health/pool'
      expect(response.parsed_body).to include('success' => true, 'runners' => {})

      get '/api/strategies/health/session'
      expect(response.parsed_body).to include('success' => true)
      expect(response.parsed_body).to have_key('entry_allowed')
    end
  end
end
