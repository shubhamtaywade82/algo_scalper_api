# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::DynamicRegimeDirectionGuard do
  let(:index_cfg) { { key: 'BANKNIFTY' } }
  let(:instrument) { instance_double(Instrument) }
  let(:series_15m) { instance_double(CandleSeries, candles: Array.new(25) { instance_double(Candle) }) }

  before do
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
    allow(instrument).to receive(:candle_series).with(interval: '15').and_return(series_15m)
  end

  it 'passes when context is for options selling (short)' do
    context = { position_side: 'short', index_cfg: index_cfg, direction: :bullish }
    expect(described_class.call(context)).to eq(:pass)
  end

  it 'blocks BUY CE when 15m regime is bearish' do
    resolver = instance_double(Market::MarketRegimeResolver, call: :bearish)
    allow(Market::MarketRegimeResolver).to receive(:new).with(candles_15m: series_15m).and_return(resolver)

    context = { position_side: 'long', index_cfg: index_cfg, direction: :bullish, instrument: instrument }
    result = described_class.call(context)

    expect(result).to be_a(Hash)
    expect(result[:blocked]).to include('BEARISH')
  end

  it 'blocks BUY PE when 15m regime is bullish' do
    resolver = instance_double(Market::MarketRegimeResolver, call: :bullish)
    allow(Market::MarketRegimeResolver).to receive(:new).with(candles_15m: series_15m).and_return(resolver)

    context = { position_side: 'long', index_cfg: index_cfg, direction: :bearish, instrument: instrument }
    result = described_class.call(context)

    expect(result).to be_a(Hash)
    expect(result[:blocked]).to include('BULLISH')
  end

  it 'passes when direction aligns with 15m regime' do
    resolver = instance_double(Market::MarketRegimeResolver, call: :bullish)
    allow(Market::MarketRegimeResolver).to receive(:new).with(candles_15m: series_15m).and_return(resolver)

    context = { position_side: 'long', index_cfg: index_cfg, direction: :bullish, instrument: instrument }
    expect(described_class.call(context)).to eq(:pass)
  end
end
