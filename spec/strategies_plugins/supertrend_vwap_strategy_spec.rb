# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'
load Rails.root.join('strategies/supertrend-vwap/strategy.rb').to_s

RSpec.describe SupertrendVwapStrategy do
  include PluginTestHelper

  let(:default_params) {
    {
      supertrend_period: 10,
      supertrend_multiplier: 3.0,
      dead_zone_start_hour: 11,
      dead_zone_end_hour: 13
    }
  }
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') }

  describe 'params_schema' do
    it 'declares doc-specified Supertrend(10,3) parameters' do
      schema = described_class.params_schema
      expect(schema[:supertrend_period][:default]).to eq(10)
      expect(schema[:supertrend_multiplier][:default]).to eq(3.0)
    end
  end

  describe 'timeframes and instruments' do
    it 'uses 5m timeframe' do
      expect(described_class.timeframes).to eq(%w[5m])
    end

    it 'supports NIFTY, BANKNIFTY, SENSEX' do
      expect(described_class.instruments).to contain_exactly('NIFTY', 'BANKNIFTY', 'SENSEX')
    end
  end

  describe '#call' do
    context 'insufficient data (fewer than 20 bars)' do
      let(:series) do
        build_series(base_date: base_date, count: 15, interval: 5, &gentle_uptrend_1m)
      end

      it 'returns Hold with insufficient_data' do
        cutoff = series.candles.last.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('insufficient_data')
      end
    end

    context 'during midday dead zone' do
      let(:series) do
        build_series(
          base_date: base_date, count: 50, interval: 5,
          &->(i, prev_close) {
            close = 25_000.0 + i * 5
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone' do
        cutoff = series.candles[24].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'late entry (after 2:30 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 80, interval: 5,
          &->(i, prev_close) {
            close = 25_000.0 + i * 3
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry_theta_risk' do
        # 5m * 67 = 335 min from 9:15 = 14:50 → late
        cutoff = series.candles[67].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry_theta_risk')
      end
    end

    context 'flat VWAP (sideways market)' do
      let(:series) do
        build_series(base_date: base_date, count: 40, interval: 5, &flat_market_1m)
      end

      it 'returns Hold with flat_vwap_no_trend' do
        cutoff = series.candles[25].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('flat_vwap_no_trend')
      end
    end

    context 'aligned bullish setup (Supertrend green + above VWAP + VWAP sloping up)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 45, interval: 5,
          &->(i, prev_close) {
            # Strong steady uptrend with volume
            close = 25_000.0 + i * 10
            {
              open: prev_close,
              high: close + 8,
              low: close - 3,   # small wicks — clean bullish
              close: close,
              volume: 150_000
            }
          }
        )
      end

      it 'does not return flat_vwap_no_trend' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        # With strong uptrend, VWAP should be sloping up
        if result.is_a?(Signals::Hold)
          expect(result.reason).not_to eq('flat_vwap_no_trend')
        end
      end
    end
  end
end
