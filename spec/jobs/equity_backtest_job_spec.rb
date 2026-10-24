# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EquityBacktestJob do
  let(:run_id) { 'run-42' }

  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = original_cache
  end

  it 'writes the presented result to cache on success' do
    backtest = instance_double(BacktestService, summary: { trades: [] })
    allow(BacktestService).to receive(:run).and_return(backtest)

    described_class.perform_now(run_id, symbol: 'NIFTY', interval: '5', days_back: 30)

    state = Rails.cache.read(described_class.cache_key(run_id))
    expect(state[:status]).to eq('completed')
    expect(state[:trades]).to eq([])
  end

  it 'writes a failed state to cache when the backtest raises' do
    allow(BacktestService).to receive(:run).and_raise(StandardError, 'dhan api down')

    described_class.perform_now(run_id, symbol: 'NIFTY', interval: '5', days_back: 30)

    state = Rails.cache.read(described_class.cache_key(run_id))
    expect(state).to eq(status: 'failed', error: 'dhan api down')
  end
end
