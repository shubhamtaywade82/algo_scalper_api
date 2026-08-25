# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DynamicConfig::ContextBuilder do
  let(:index_cfg) do
    { key: 'NIFTY', capital_alloc_pct: 0.25, risk_model: { base_risk_pct: 0.01 },
      adx_thresholds: { primary_min_strength: 15 }, premium_band: { min: 30, max: 160 },
      cooldown_sec: 300, trade_limits: { max_trades_per_day: 5 } }
  end

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: false })
  end

  it 'returns nil regime/chain when no instrument is configured' do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)

    result = described_class.call(index_key: 'NIFTY')

    expect(result[:index_key]).to eq('NIFTY')
    expect(result[:regime]).to be_nil
    expect(result[:chain]).to be_nil
  end

  it 'includes the current allow-listed config slice for the index' do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)

    result = described_class.call(index_key: 'NIFTY')

    expect(result[:current_config][:capital_alloc_pct]).to eq(0.25)
    expect(result[:current_config][:cooldown_sec]).to eq(300)
  end

  it 'never raises when the chain analyzer blows up, and returns nil chain instead' do
    instrument = instance_double(Instrument, candle_series: nil)
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
    allow(Options::ChainAnalyzer).to receive(:new).and_raise(StandardError, 'boom')

    expect { described_class.call(index_key: 'NIFTY') }.not_to raise_error
    expect(described_class.call(index_key: 'NIFTY')[:chain]).to be_nil
  end

  it 'reports today\'s risk snapshot' do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)
    create(:position_tracker, :exited, exited_at: 1.hour.ago, last_pnl_rupees: -100)

    result = described_class.call(index_key: 'NIFTY')

    expect(result[:risk][:circuit_breaker_tripped]).to be false
    expect(result[:risk][:today_realized_pnl_rupees]).to eq(-100.0)
  end
end
