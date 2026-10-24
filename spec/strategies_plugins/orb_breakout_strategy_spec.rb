# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'
load Rails.root.join('strategies/orb-breakout/strategy.rb').to_s

RSpec.describe OrbBreakoutStrategy do
  include PluginTestHelper

  let(:default_params) do
    {
      range_minutes: 30,
      min_range_pct: 0.20,
      max_gap_pct: 0.80,
      volume_multiplier: 1.5,
      force_exit_hour: 14,
      force_exit_minute: 30
    }
  end
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') } # A Monday

  describe 'params_schema' do
    it 'declares the parameters the strategy reads (per manifest)', :aggregate_failures do
      schema = described_class.params_schema
      expect(schema[:range_minutes][:default]).to eq(30)
      expect(schema[:min_range_pct][:default]).to eq(0.20)
      expect(schema[:max_gap_pct][:default]).to eq(0.80)
      expect(schema[:volume_multiplier][:default]).to eq(1.5)
      expect(schema[:force_exit_hour][:default]).to eq(14)
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
    context 'when in ORB formation (before ORB period completes)' do
      let(:series) do
        build_series(base_date: base_date, count: 25, interval: 1, &gentle_uptrend_1m)
      end

      it 'returns Hold with range_forming reason' do
        # 25 1m candles = 25 min, ORB period is 30 min + 5 min buffer = need 35 min
        context = build_context(series: series, cutoff: series.candles.last.timestamp)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('range_forming')
      end
    end

    context 'when after ORB period with a valid CE breakout' do
      let(:series) do
        # Build 45 1m candles where:
        # - First 30 form the ORB (range high ~25050, range low ~24950 = 100pt range)
        # - Candle 35 breaks above range high with volume
        build_series(
          base_date: base_date, count: 45, interval: 1,
          &lambda { |i, prev_close|
            if i < 30
              # ORB formation: oscillate in 24950-25050 range
              close = 25_000.0 + ((rand - 0.5) * 100)
              {
                open: prev_close,
                high: [close, prev_close].max + 10,
                low: [close, prev_close].min - 10,
                close: close,
                volume: 100_000
              }
            elsif i == 35
              # Breakout candle: close above range high. Volume must clear the filter
              # on its own: the 5m rollup buckets it alone (candles 36-39 are past the
              # cutoff), so this single candle is compared against 1.5x the average
              # ROLLED-UP range bucket (5 x 100_000).
              {
                open: 25_050.0,
                high: 25_200.0,
                low: 25_030.0,
                close: 25_180.0, # close above range high
                volume: 1_000_000 # 2x the rolled-up 5m range-bucket average
              }
            else
              {
                open: prev_close,
                high: prev_close + 10,
                low: prev_close - 10,
                close: prev_close + 2,
                volume: 100_000
              }
            end
          }
        )
      end

      it 'returns BuyCall with orb_breakout_up reason' do
        # Use candle at index 35 (the breakout candle)
        breakout_candle = series.candles[35]
        cutoff = breakout_candle.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)

        expect(result).to be_a(Signals::BuyCall)
        expect(result.reason).to include('orb_breakout_up')
        expect(result.confidence).to be >= 0.5
      end
    end

    context 'when a CE breakout already resolved today (per-direction cap)' do
      # Doc contract: one signal per direction per day (max 2 trades/day — one
      # CE break, one PE break). A resolved CE break retires only the CE side.
      #
      # Shared day shape (1m candles, rolled up to 5m by the context):
      #   09:15-09:44  ORB formation — deterministic oscillation, range ~24930-25050
      #   09:45        inside the range
      #   09:50        closes 25,180 above ORH — the CE side has resolved
      #   09:55        back inside the range (no failed-breakout wicks)
      #   10:00        current bucket; its final candle (i=49) sets the close
      # `final_candle` decides what the evaluating bar closes as.
      def ce_resolved_day_series(final_candle)
        build_series(
          base_date: base_date, count: 50, interval: 1,
          &lambda { |i, _prev_close|
            if i < 30
              close = i.even? ? 25_040.0 : 24_960.0
              { open: close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
            elsif i < 35
              { open: 25_020.0, high: 25_030.0, low: 25_010.0, close: 25_020.0, volume: 100_000 }
            elsif i < 39
              { open: 25_010.0, high: 25_020.0, low: 25_000.0, close: 25_010.0, volume: 100_000 }
            elsif i == 39
              { open: 25_010.0, high: 25_200.0, low: 25_000.0, close: 25_180.0, volume: 1_000_000 }
            elsif i < 45
              { open: 25_020.0, high: 25_040.0, low: 25_010.0, close: 25_030.0, volume: 1_000_000 }
            elsif i < 49
              { open: 25_020.0, high: 25_030.0, low: 25_010.0, close: 25_020.0, volume: 100_000 }
            else
              final_candle.merge(volume: 1_000_000)
            end
          }
        )
      end

      it 'blocks a second CE breakout with already_resolved_today' do
        # CE side already resolved (09:50 bucket closed above ORH); the current
        # bar closes above ORH again — a second CE attempt the one-per-direction
        # cap must block.
        rebreak = ce_resolved_day_series({ open: 25_110.0, high: 25_220.0, low: 25_100.0, close: 25_200.0 })
        cutoff = rebreak.candles[49].timestamp
        context = build_context(series: rebreak, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('already_resolved_today')
      end

      it 'still allows the PE breakout on the opposite side (2 trades/day: one CE, one PE)' do
        # Same day, CE side already resolved (09:50 bucket closed above ORH);
        # the current bar closes below ORL — the doc's one-per-direction cap
        # must let this PE signal through (the old any-direction gate blocked
        # both sides after the first break, capping the day at 1 trade).
        series = ce_resolved_day_series({ open: 25_020.0, high: 25_030.0, low: 24_790.0, close: 24_800.0 })
        cutoff = series.candles[49].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::BuyPut)
        expect(result.reason).to include('orb_breakout_down')
      end
    end

    context 'when range is too narrow' do
      let(:strategy_narrow) do
        described_class.new(params: default_params.merge(min_range_pct: 0.15))
      end
      let(:series) do
        # Only 20pt range
        build_series(
          base_date: base_date, count: 40, interval: 1,
          &lambda { |i, prev_close|
            if i < 30
              close = 25_000.0 + ((rand - 0.5) * 20) # tiny range
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

    context 'when in midday dead zone (11:00 AM - 1:00 PM)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 120, interval: 1,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 0.3)
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone reason at 11:30 AM' do
        pending "the doc's 11:00-13:00 midday dead-zone gate is not implemented for " \
               'OrbBreakoutStrategy yet; it currently evaluates breakouts through midday'

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

    context 'when past force_exit_time' do
      let(:series) do
        build_series(
          base_date: base_date, count: 330, interval: 1,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 0.1)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with past_force_exit_time reason after 14:30' do
        pending 'a past-force-exit-time entry gate is not implemented for ' \
               'OrbBreakoutStrategy yet; force_exit_hour/minute currently only build ' \
               'the exit_rules metadata, they do not suppress entries'

        # 14:30 = 9:15 + 315 min = index 315
        cutoff = series.candles[315].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('past_force_exit_time')
      end
    end

    context 'with breakout without volume confirmation' do
      let(:series) do
        build_series(
          base_date: base_date, count: 45, interval: 1,
          &lambda { |i, prev_close|
            if i < 30
              close = 25_000.0 + ((rand - 0.5) * 100)
              { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
            elsif i == 35
              # Breakout but LOW volume
              {
                open: 25_050.0,
                high: 25_200.0,
                low: 25_030.0,
                close: 25_180.0,
                volume: 50_000 # below 1.5x average
              }
            else
              { open: prev_close, high: prev_close + 10, low: prev_close - 10, close: prev_close + 2, volume: 100_000 }
            end
          }
        )
      end

      it 'returns Hold with volume_filter' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to include('volume_filter')
      end
    end

    context 'when price inside ORB range' do
      let(:series) do
        build_series(
          base_date: base_date, count: 40, interval: 1,
          &lambda { |_i, prev_close|
            close = 25_000.0 + ((rand - 0.5) * 80) # stays within range
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with inside_range reason' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to include('inside_range')
      end
    end
  end
end
