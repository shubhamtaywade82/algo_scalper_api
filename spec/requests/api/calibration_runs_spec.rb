# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::CalibrationRuns' do
  def create_run(symbol: 'NIFTY', applied_at: nil)
    CalibrationRun.create!(
      symbol: symbol, weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2 },
      proposed_patch: { 'risk' => { 'percentage_pnl_exit' => { 'target_pct' => 0.064 } } },
      applied_at: applied_at
    )
  end

  describe 'GET /api/calibration_runs' do
    before { create_run }

    it 'returns 200 with an array of runs' do
      get '/api/calibration_runs'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.size).to be >= 1
    end

    it 'includes current_snapshot in each run' do
      get '/api/calibration_runs'
      json = response.parsed_body
      expect(json.first).to have_key('current_snapshot')
    end

    it 'respects limit param' do
      5.times { create_run }
      get '/api/calibration_runs', params: { limit: 3 }
      json = response.parsed_body
      expect(json.size).to be <= 3
    end
  end

  describe 'GET /api/calibration_runs/:id' do
    let(:run) { create_run }

    it 'returns 200 with the run' do
      get "/api/calibration_runs/#{run.id}"
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['id']).to eq(run.id)
    end

    it 'includes current_snapshot in the response' do
      get "/api/calibration_runs/#{run.id}"
      json = response.parsed_body
      expect(json).to have_key('current_snapshot')
    end

    it 'returns 404 for unknown id' do
      get '/api/calibration_runs/999999'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/calibration_runs/:id/apply' do
    let(:run) { create_run }
    let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

    before do
      ENV['API_OPERATOR_TOKEN'] = 'spec-operator-token'
      Setting.put(doc_key, { mode: 'paper', risk: {} }.to_json)
      AlgoConfig.reset!
    end

    after do
      Setting.where(key: doc_key).delete_all
      AlgoConfigChangeLog.delete_all
      AlgoConfig.reset!
    end

    it 'returns 200 on success' do
      post "/api/calibration_runs/#{run.id}/apply",
           headers: { 'Authorization' => 'Bearer spec-operator-token' }
      expect(response).to have_http_status(:ok)
    end

    it 'returns applied_at in the response' do
      post "/api/calibration_runs/#{run.id}/apply",
           headers: { 'Authorization' => 'Bearer spec-operator-token' }
      json = response.parsed_body
      expect(json['applied_at']).to be_present
    end

    it 'returns 422 on double-apply' do
      run.update!(applied_at: Time.current)
      post "/api/calibration_runs/#{run.id}/apply",
           headers: { 'Authorization' => 'Bearer spec-operator-token' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for unknown id' do
      post '/api/calibration_runs/999999/apply',
           headers: { 'Authorization' => 'Bearer spec-operator-token' }
      expect(response).to have_http_status(:not_found)
    end
  end
end
