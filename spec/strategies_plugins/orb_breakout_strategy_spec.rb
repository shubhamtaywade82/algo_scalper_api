# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'

RSpec.describe OrbBreakoutStrategy do
  include PluginTestHelper

  let(:default_params) {
    {
      orb_period_minutes: 30,
      min_range_points: 40.0,
      max_open_gap_pct: 0.8,
      volume_multiplier: 1.5,
      max_trades_per_day: 2,
      force_exit_time: '14:30'
    }
  }
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') } # A Monday

  describe 'params_schema' do
    it 'declares all doc-specified parameters with defaults' do
      schema = described_class.params_schema
      expect(schema[:orb_period_minutes][:default]).to eq(30)
      expect(schema[:min_range_points][:default]).to eq(40.0)
      expect(schema[:max_open_gap_pct][:default]).to eq(0.8)
      expect(schema[:volume_multiplier][:default]).to eq(1.5)
      expect(schema[:max_trades_per_day][:default]).to eq(2)
    end
  end
  describe 'timeframes and instruments' do
    it 'uses 1m timeframe' do
      expect(described_class.timeframes).to eq(%w[1m])
    end

    it 'supports NIFTY, BANKNIFTY, SENSEX' do
      expect(described_class.instruments).to contain_exactly('NIFTY', 'BANKNIFTY', 'SENSEX')
    end
  end

  describe '#call' do
    context 'during ORB formation (before ORB period completes)' do
      let(:series) do
        build_series(base_date: base_date, count: 25, interval: 1, &gentle_uptrend_1m)
      end

      it 'returns Hold with orb_forming reason' do
        # 25 1m candles = 25 min, ORB period is 30 min + 5 min buffer = need 35 min
        context = build_context(series: series, cutoff: series.candles.last.timestamp)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('orb_forming')
      end
    end

    context 'after ORB period with a valid CE breakout' do
      let(:series) do
        # Build 45 1m candles where:
        # - First 30 form the ORB (range high ~25050, range low ~24950 = 100pt range)
        # - Candle 35 breaks above range high with volume
        build_series(
          base_date: base_date, count: 45, interval: 1,
          &->(i, prev_close) {
            if i < 30
              # ORB formation: oscillate in 24950-25050 range
              close = 25_000.0 + (rand - 0.5) * 100
              {
                open: prev_close,
                high: [close, prev_close].max + 10,
                low:  [close, prev_close].min - 10,
                close: close,
                volume: 100_000
              }
            elsif i == 35
              # Breakout candle: close above range high
              {
                open: 25_050.0,
                high: 25_200.0,
                low: 25_030.0,
                close: 25_180.0,  # close above range high
                volume: 300_000  # 3x avg volume
              }
            else
              {
                open: prev_close,
                high: prev_close + 10,
                low:  prev_close - 10,
                close: prev_close + 2,
                volume: 100_000
              }
            end
          }
        )
      end

      it 'returns BuyCall with orb_ce_breakout reason' do
        # Use candle at index 35 (the breakout candle)
        breakout_candle = series.candles[35]
        cutoff = breakout_candle.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)

        expect(result).to be_a(Signals::BuyCall)
        expect(result.reason).to include('orb_ce_breakout')
        expect(result.confidence).to be >= 0.5
      end
    end

    context 'when range is too narrow' do
      let(:strategy_narrow) do
        described_class.new(params: default_params.merge(min_range_points: 200.0))
      end
      let(:series) do
        # Only 20pt range
        build_series(
          base_date: base_date, count: 40, interval: 1,
          &->(i, prev_close) {
            if i < 30
              close = 25_000.0 + (rand - 0.5) * 20  # tiny range
              { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
            else
              { open: prev_close, high: 25_030, low: 24_990, close: 25_020, volume: 200_000 }
            end
          }
        )
      end

      it 'returns Hold with range_too_narrow reason' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy_narrow.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to include('range_too_narrow')
      end
    end

    context 'during midday dead zone (11:00 AM - 1:00 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 120, interval: 1,
          &->(i, prev_close) {
            close = 25_000.0 + i * 0.3
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone reason at 11:30 AM' do
        # 11:30 AM = 135 min after 9:15 = index 135 (but we only have 120 candles, so use index 110 = ~10:45)
        # Actually let me check: index 105 = 9:15 + 105 min = 11:00. Index 115 = 11:10
        dead_zone_candle = series.candles[115]
        cutoff = dead_zone_candle.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'past force_exit_time' do
      let(:series) do
        build_series(
          base_date: base_date, count: 330, interval: 1,
          &->(i, prev_close) {
            close = 25_000.0 + i * 0.1
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with past_force_exit_time reason after 14:30' do
        # 14:30 = 9:15 + 315 min = index 315
        cutoff = series.candles[315].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('past_force_exit_time')
      end
    end

    context 'breakout without volume confirmation' do
      let(:series) do
        build_series(
          base_date: base_date, count: 45, interval: 1,
          &->(i, prev_close) {
            if i < 30
              close = 25_000.0 + (rand - 0.5) * 100
              { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
            elsif i == 35
              # Breakout but LOW volume
              {
                open: 25_050.0,
                high: 25_200.0,
                low: 25_030.0,
                close: 25_180.0,
                volume: 50_000  # below 1.5x average
              }
            else
              { open: prev_close, high: prev_close + 10, low: prev_close - 10, close: prev_close + 2, volume: 100_000 }
            end
          }
        )
      end

      it 'returns Hold with orb_break_no_volume_confirmation' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to include('no_volume_confirmation')
      end
    end

    context 'price inside ORB range' do
      let(:series) do
        build_series(
          base_date: base_date, count: 40, interval: 1,
          &->(i, prev_close) {
            close = 25_000.0 + (rand - 0.5) * 80  # stays within range
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with inside_orb_range reason' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to include('inside_orb_range')
      end
    end
  end
end
