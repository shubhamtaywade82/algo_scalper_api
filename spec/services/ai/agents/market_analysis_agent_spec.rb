# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::MarketAnalysisAgent do
  subject(:agent) { described_class.new }

  it 'reports zero confidence when no instrument is configured for the index_key' do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([])

    result = agent.run(index_key: 'NIFTY')
    expect(result[:output][:note]).to include('no instrument')
    expect(result[:confidence]).to eq(0.0)
  end

  it 'publishes :regime_change and returns the composed snapshot when data is available' do
    idx_cfg = { key: 'NIFTY' }
    instrument = instance_double(Instrument)
    series = instance_double(CandleSeries, blank?: false, candles: [Object.new])
    snapshot = MarketContext::RegimeSnapshot.new(
      structure: 'trending', strength: 'strong', volatility_state: 'normal',
      participation: 'high', conviction_score: 72.0, displacement: 1.2,
      legacy_regime: 'trending', legacy_confidence: 0.8, raw: {}
    )

    allow(IndexConfigLoader).to receive(:load_indices).and_return([idx_cfg])
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(idx_cfg).and_return(instrument)
    allow(instrument).to receive(:candle_series).with(interval: '5').and_return(series)
    allow(MarketContext::RegimeComposer).to receive(:new).with(series: series, index_key: 'NIFTY')
                                                         .and_return(instance_double(MarketContext::RegimeComposer, call: snapshot))

    received = nil
    Core::EventBus.instance.subscribe(:regime_change) { |event| received = event }

    result = agent.run(index_key: 'NIFTY')

    expect(result[:output][:structure]).to eq('trending')
    expect(result[:confidence]).to eq(0.72)
    expect(received).to include(index_key: 'NIFTY', structure: 'trending')
  end
end
