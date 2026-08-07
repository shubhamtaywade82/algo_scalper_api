# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::BacktestRuns' do
  describe 'POST /api/backtest_runs' do
    it 'creates a pending run and enqueues the job, returning 202 immediately' do
      allow(BacktestRunJob).to receive(:perform_later)

      post '/api/backtest_runs', params: { symbol: 'niftY', days_back: 45, params: { stop_loss_pct: 0.4 } }

      expect(response).to have_http_status(:accepted)
      run = BacktestRun.last
      expect(BacktestRunJob).to have_received(:perform_later).with(run.id)
      expect(run.symbol).to eq('NIFTY')
      expect(run.days_back).to eq(45)
      expect(run.params).to eq('stop_loss_pct' => 0.4)
      expect(run.status).to eq('pending')
      expect(response.parsed_body).to eq('backtest_run_id' => run.id, 'status' => 'pending')
    end

    it 'clamps days_back to MAX_DAYS_BACK' do
      post '/api/backtest_runs', params: { days_back: 9999 }

      expect(BacktestRun.last.days_back).to eq(Api::BacktestRunsController::MAX_DAYS_BACK)
    end

    it 'defaults symbol to NIFTY and days_back to 90 when omitted' do
      post '/api/backtest_runs'

      run = BacktestRun.last
      expect(run.symbol).to eq('NIFTY')
      expect(run.days_back).to eq(90)
    end

    it 'drops unknown param keys and non-numeric values instead of passing them through to the job' do
      post '/api/backtest_runs', params: { params: { stop_loss_pct: '0.3', not_a_real_param: 'x', target_pct: 'garbage' } }

      expect(BacktestRun.last.params).to eq('stop_loss_pct' => 0.3)
    end
  end

  describe 'GET /api/backtest_runs' do
    it 'lists runs newest first with pagination meta' do
      create(:backtest_run, :completed, created_at: 2.days.ago)
      newest = create(:backtest_run, :failed, created_at: 1.day.ago)

      get '/api/backtest_runs'

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['runs'].first['id']).to eq(newest.id)
      expect(body['meta']['total']).to eq(2)
    end
  end

  describe 'GET /api/backtest_runs/:id' do
    it 'returns full detail including results once completed' do
      run = create(:backtest_run, :completed)

      get "/api/backtest_runs/#{run.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['status']).to eq('completed')
      expect(body['results']).to be_present
    end
  end

  describe 'GET /api/backtest_runs/:id/download_csv' do
    it 'returns a CSV of trades for a completed run' do
      run = create(:backtest_run, :completed)

      get "/api/backtest_runs/#{run.id}/download_csv"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/csv')
      expect(response.body).to include('EntryTime,ExitTime')
    end

    it 'returns 422 for a run that has not completed yet' do
      run = create(:backtest_run, status: 'running')

      get "/api/backtest_runs/#{run.id}/download_csv"

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'existing synchronous Api::BacktestsController is untouched' do
    it 'still routes POST /api/backtests to the original controller/action' do
      route = Rails.application.routes.recognize_path('/api/backtests', method: :post)

      expect(route).to eq(controller: 'api/backtests', action: 'create')
    end
  end
end
