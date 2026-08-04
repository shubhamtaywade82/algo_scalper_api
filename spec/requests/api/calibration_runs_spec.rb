# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::CalibrationRunsController' do
  let(:headers) { { 'X-Dashboard-Token' => ENV.fetch('DASHBOARD_TOKEN', 'test-dashboard-token') } }

  describe 'GET /api/calibration_runs' do
    it 'returns calibration runs' do
      run = CalibrationRun.create!(
        symbol: 'NIFTY',
        weeks_analyzed: 52,
        strike_mode: 'atm_plus_minus',
        raw_stats: { avg_gain: 10.0 },
        proposed_patch: { 'risk' => { 'trailing' => { 'activation_pct' => 0.04 } } }
      )

      get '/api/calibration_runs', headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['runs'].map { |r| r['id'] }).to include(run.id)
      expect(body['current_snapshot']).to be_a(Hash)
    end
  end

  describe 'POST /api/calibration_runs/:id/apply' do
    around do |example|
      prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
      ENV.delete('SETTINGS_UPDATE_TOKEN')
      example.run
    ensure
      if prior
        ENV['SETTINGS_UPDATE_TOKEN'] = prior
      else
        ENV.delete('SETTINGS_UPDATE_TOKEN')
      end
    end

    it 'applies a pending run' do
      run = CalibrationRun.create!(
        symbol: 'NIFTY',
        weeks_analyzed: 52,
        strike_mode: 'atm_plus_minus',
        raw_stats: {},
        proposed_patch: { 'risk' => { 'trailing' => { 'drawdown_pct' => 0.031 } } }
      )

      post "/api/calibration_runs/#{run.id}/apply"

      expect(response).to have_http_status(:ok)
      expect(run.reload.applied_at).to be_present
    end

    it 'returns 422 when already applied' do
      run = CalibrationRun.create!(
        symbol: 'NIFTY',
        weeks_analyzed: 52,
        strike_mode: 'atm_plus_minus',
        raw_stats: {},
        proposed_patch: { 'risk' => { 'trailing' => { 'drawdown_pct' => 0.031 } } },
        applied_at: 1.hour.ago,
        applied_by: 'spec'
      )

      post "/api/calibration_runs/#{run.id}/apply"

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
