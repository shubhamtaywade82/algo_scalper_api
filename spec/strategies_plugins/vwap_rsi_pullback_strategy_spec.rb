# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'
load Rails.root.join('strategies/vwap-rsi-pullback/strategy.rb').to_s

RSpec.describe VwapRsiPullbackStrategy do
  include PluginTestHelper

  let(:default_params) do
    {
      rsi_period: 14,
      rsi_pullback_zone_low: 40.0,
      rsi_pullback_zone_high: 60.0,
      vwap_band_pct: 0.1,
      min_slope_per_bar: 0.002,
      dead_zone_start_hour: 11,
      dead_zone_end_hour: 13
    }
  end
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') }

  describe 'params_schema' do
    it 'declares doc-specified parameters' do
      schema = described_class.params_schema
      expect(schema[:rsi_period][:default]).to eq(14)
      expect(schema[:rsi_pullback_zone_low][:default]).to eq(40.0)
      expect(schema[:rsi_pullback_zone_high][:default]).to eq(60.0)
      expect(schema[:vwap_band_pct][:default]).to eq(0.1)
    end
  end

  describe 'timeframes and instruments' do
    it 'uses 3m timeframe' do
      expect(described_class.timeframes).to eq(%w[3m])
    end

    it 'supports NIFTY, BANKNIFTY, SENSEX' do
      expect(described_class.instruments).to contain_exactly('NIFTY', 'BANKNIFTY', 'SENSEX')
    end
  end

  describe '#call' do
    context 'when warming up (before 9:30 AM)' do
      let(:series) do
        build_series(base_date: base_date, count: 3, interval: 3, &gentle_uptrend_1m)
      end

      it 'returns Hold with warming_up_vwap' do
        cutoff = series.candles.last.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('warming_up_vwap')
      end
    end

    context 'with flat VWAP (no trend)' do
      let(:series) do
        build_series(base_date: base_date, count: 30, interval: 3, &flat_market_1m)
      end

      it 'returns Hold with flat_vwap_no_trend' do
        # Skip to candle 15 (10:00 AM, past warmup, before dead zone)
        cutoff = series.candles[15].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        # A perfectly flat price series has a zero VWAP slope in any unit system,
        # so the flat-VWAP gate must fire deterministically now that the slope is
        # price-normalized (it used to be compared in raw points against 0.002,
        # which on 25,000-scale prices let almost anything through as "sloping").
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('flat_vwap_no_trend')
      end
    end

    context 'with a gently sloping VWAP below a raised min_slope_per_bar' do
      # ~2 pts/bar drift on a 25,000 base = ~0.008%/bar — well below the raised
      # 0.05 (%/bar) threshold but far above it in RAW points (2 > 0.05). Under
      # the old raw-points comparison this series always counted as "sloping";
      # with the percent-normalized slope it must be rejected as flat.
      let(:strategy_strict) { described_class.new(params: default_params.merge(min_slope_per_bar: 0.05)) }
      let(:series) do
        build_series(
          base_date: base_date, count: 30, interval: 3,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 2)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with flat_vwap_no_trend (slope threshold is in %/bar, not points)' do
        cutoff = series.candles[25].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy_strict.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('flat_vwap_no_trend')
      end

      it 'passes the flat-VWAP gate with the default 0.002 %/bar threshold' do
        cutoff = series.candles[25].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        # ~0.008%/bar clears the 0.002 %/bar default, so the gate must NOT fire
        # (the strategy may still Hold for other reasons: RSI zone, proximity...).
        flat_blocked = result.is_a?(Signals::Hold) && result.reason == 'flat_vwap_no_trend'
        expect(flat_blocked).to be(false)
      end
    end

    context 'when in midday dead zone (11:00 AM - 1:00 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 50, interval: 3,
          &lambda { |i, prev_close|
            # Steady uptrend to establish VWAP slope
            close = 25_000.0 + (i * 3)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone reason' do
        # 3m candles: index 0 = 9:15, index 5 = 9:30, index 35 = 10:30, index 45 = 11:00
        # Actually: 3m * 45 = 135 min from 9:15 = 11:30 AM → dead zone
        dead_zone_idx = 45
        cutoff = series.candles[dead_zone_idx].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'with late entry (at/after 2:30 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 120, interval: 3,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 2)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry_theta_risk at exactly 14:30' do
        # 3m candles from 9:15: 14:30 = 315 min elapsed = index 105
        cutoff = series.candles[105].timestamp
        expect(cutoff.in_time_zone('Asia/Kolkata').strftime('%H:%M')).to eq('14:30')
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry_theta_risk')
      end

      it 'returns Hold with late_entry_theta_risk in the 15:00-15:29 window (regression)' do
        # 15:03 = 348 min from 9:15 = index 116. The old gate
        # (`hour >= 14 && min >= 30`) let every 15:00-15:29 candle through
        # (hour=15>=14 true, min<30 false -> AND fails), exactly the final
        # half-hour theta window the rule exists to block.
        cutoff = series.candles[116].timestamp
        expect(cutoff.in_time_zone('Asia/Kolkata').strftime('%H:%M')).to eq('15:03')
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry_theta_risk')
      end

      it 'does not apply the late-entry gate before 14:30' do
        # 14:27 = index 104 — one candle before the cutoff; must pass the gate
        # (the strategy may still Hold for setup reasons, just not this one).
        cutoff = series.candles[104].timestamp
        expect(cutoff.in_time_zone('Asia/Kolkata').strftime('%H:%M')).to eq('14:27')
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        late_blocked = result.is_a?(Signals::Hold) && result.reason == 'late_entry_theta_risk'
        expect(late_blocked).to be(false)
      end
    end

    context 'with a 15:05-completing bar (rolled up from 1m)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 351, interval: 1,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 0.5)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry_theta_risk for the 15:05 candle' do
        # 1m candles 9:15..15:05 (index 350). The context rolls them up to 3m;
        # the final bucket (15:03-15:05) completes at 15:05 and evaluates in
        # the previously-ungated 15:00-15:29 window.
        cutoff = series.candles[350].timestamp
        expect(cutoff.in_time_zone('Asia/Kolkata').strftime('%H:%M')).to eq('15:05')
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry_theta_risk')
      end
    end

    context 'with uptrend and pullback to VWAP' do
      let(:series) do
        build_series(
          base_date: base_date, count: 40, interval: 3,
          &lambda { |i, prev_close|
            if i < 20
              # Strong uptrend
              close = 25_000.0 + (i * 5)
            elsif i == 25
              # Pullback to near VWAP (VWAP should be around 25040 ish)
              close = 25_035.0
            else
              close = prev_close + 1
            end
            { open: prev_close, high: close + 3, low: close - 3, close: close, volume: 100_000 }
          }
        )
      end

      it 'does not return Hold with flat_vwap_no_trend (VWAP is sloping)' do
        # At index 25 (pullback candle), VWAP should be sloping up
        cutoff = series.candles[25].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        # The result should NOT be flat_vwap — it may still be Hold for other reasons
        # (RSI not in zone, not near VWAP, etc.)
        if result.is_a?(Signals::Hold)
          expect(result.reason).not_to eq('flat_vwap_no_trend')
        end
      end
    end
  end
end
