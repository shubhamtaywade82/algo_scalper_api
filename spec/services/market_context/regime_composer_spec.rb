# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketContext::RegimeComposer do
  let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }

  before do
    12.times do |i|
      series.add_candle(
        Candle.new(
          timestamp: Time.zone.parse('2026-03-02 09:15') + i.minutes,
          open: 100 + i * 0.2,
          high: 102 + i * 0.2,
          low: 99 + i * 0.2,
          close: 101 + i * 0.2,
          volume: 500_000 + i * 10_000
        )
      )
    end
    allow(MarketRegimeDetector).to receive(:new).with(series).and_return(
      instance_double(
        MarketRegimeDetector,
        detect: {
          regime: 'TRENDING_UP',
          confidence: 72.0,
          metrics: {
            adx_value: 55.0,
            volatility_regime: 'LOW_VOL',
            atr_percent: 0.006
          }
        }
      )
    )
  end

  describe '#call' do
    it 'returns a RegimeSnapshot with conviction in 0..100' do
      snap = described_class.new(series: series, index_key: 'NIFTY').call

      expect(snap).to be_a(MarketContext::RegimeSnapshot)
      expect(snap.conviction_score).to be_between(0, 100)
      expect(snap.legacy_regime).to eq('TRENDING_UP')
      expect(snap.raw).to include(:legacy, :structure, :volatility, :participation)
    end
  end
end
