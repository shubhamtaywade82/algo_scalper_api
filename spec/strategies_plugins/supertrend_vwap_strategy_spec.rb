# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'
load Rails.root.join('strategies/supertrend-vwap/strategy.rb').to_s

RSpec.describe SupertrendVwapStrategy do
  include PluginTestHelper

  let(:default_params) do
    {
      supertrend_period: 10,
      supertrend_multiplier: 3.0,
      dead_zone_start_hour: 11,
      dead_zone_end_hour: 13
    }
  end
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
    context 'with insufficient data (fewer bars than the Supertrend period needs)' do
      let(:series) do
        # Supertrend(period: 10) needs period + 1 = 11 bars; 8 leaves it unable to
        # compute, which the strategy surfaces as supertrend_unavailable.
        build_series(base_date: base_date, count: 8, interval: 5, &gentle_uptrend_1m)
      end

      it 'returns Hold with supertrend_unavailable' do
        cutoff = series.candles.last.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('supertrend_unavailable')
      end
    end

    context 'when in midday dead zone' do
      let(:series) do
        build_series(
          base_date: base_date, count: 50, interval: 5,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 5)
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone' do
        pending "the doc's 11:00-13:00 midday dead-zone gate is not implemented for " \
               'SupertrendVwapStrategy yet; it currently evaluates through midday'

        cutoff = series.candles[24].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'with late entry (after 2:30 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 80, interval: 5,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 3)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry_theta_risk' do
        pending "the doc's after-14:30 late-entry theta-risk gate is not implemented " \
               'for SupertrendVwapStrategy yet; it currently evaluates until close'

        # 5m * 67 = 335 min from 9:15 = 14:50 → late
        cutoff = series.candles[67].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry_theta_risk')
      end
    end

    context 'with flat VWAP (sideways market)' do
      let(:series) do
        build_series(base_date: base_date, count: 40, interval: 5, &flat_market_1m)
      end

      it 'returns Hold with trend_vwap_not_aligned' do
        cutoff = series.candles[20].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('trend_vwap_not_aligned')
      end
    end

    context 'with aligned bullish setup (Supertrend green + above VWAP + VWAP sloping up)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 45, interval: 5,
          &lambda { |i, prev_close|
            # Strong steady uptrend with volume
            close = 25_000.0 + (i * 10)
            {
              open: prev_close,
              high: close + 8,
              low: close - 3, # small wicks — clean bullish
              close: close,
              volume: 150_000
            }
          }
        )
      end

      it 'does not return trend_vwap_not_aligned' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        # With strong uptrend, price stays above VWAP and the Supertrend line
        if result.is_a?(Signals::Hold)
          expect(result.reason).not_to eq('trend_vwap_not_aligned')
        end
      end
    end
  end
end
