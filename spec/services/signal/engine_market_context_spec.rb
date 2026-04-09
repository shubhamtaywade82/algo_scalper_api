# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine do
  describe '.evaluate_market_context_for_entry' do
    let(:series) { CandleSeries.new(symbol: 'NIFTY', interval: '5') }
    let(:pick) { { strike: 24_500.0 } }

    before do
      12.times do |i|
        series.add_candle(
          Candle.new(
            timestamp: Time.zone.parse('2026-03-02 09:15') + i.minutes,
            open: 100 + (i * 0.2),
            high: 102 + (i * 0.2),
            low: 99 + (i * 0.2),
            close: 101 + (i * 0.2),
            volume: 500_000
          )
        )
      end
      allow(MarketRegimeDetector).to receive(:new).and_return(
        instance_double(
          MarketRegimeDetector,
          detect: {
            regime: 'TRENDING_UP',
            confidence: 80.0,
            metrics: { adx_value: 60.0, volatility_regime: 'LOW_VOL', atr_percent: 0.006 }
          }
        )
      )
    end

    it 'returns empty extra when market_context is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return(market_context: { enabled: false })

      extra, blocked, detail = described_class.send(
        :evaluate_market_context_for_entry,
        index_cfg: { key: 'NIFTY' },
        primary_series: series,
        expiry_date: 1.week.from_now.to_date,
        chain_data: { last_price: 24_500.0, oc: {} },
        final_direction: :bullish,
        pick: pick
      )

      expect(extra).to eq({})
      expect(blocked).to be false
      expect(detail).to be_nil
    end

    it 'returns metadata and does not block when gate is off' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        market_context: {
          enabled: true,
          gate: { enabled: false }
        }
      )

      extra, blocked, detail = described_class.send(
        :evaluate_market_context_for_entry,
        index_cfg: { key: 'NIFTY' },
        primary_series: series,
        expiry_date: 1.week.from_now.to_date,
        chain_data: { last_price: 24_500.0, oc: {} },
        final_direction: :bullish,
        pick: pick
      )

      expect(blocked).to be false
      expect(detail).to be_nil
      expect(extra[:strategy_profile]).to be_present
      expect(extra[:market_context_conviction]).to be_a(Integer)
    end
  end
end
