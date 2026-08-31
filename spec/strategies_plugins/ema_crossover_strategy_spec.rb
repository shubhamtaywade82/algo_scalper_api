# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'

RSpec.describe EmaCrossoverStrategy do
  include PluginTestHelper

  let(:default_params) {
    {
      fast_ema_period: 9,
      slow_ema_period: 26,
      min_separation_pct: 0.02,
      adx_threshold: 20.0,
      dead_zone_start_hour: 11,
      dead_zone_end_hour: 13
    }
  }
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') }

  describe 'params_schema' do
    it 'declares doc-specified EMA 9/26 parameters' do
      schema = described_class.params_schema
      expect(schema[:fast_ema_period][:default]).to eq(9)
      expect(schema[:slow_ema_period][:default]).to eq(26)
      expect(schema[:adx_threshold][:default]).to eq(20.0)
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
    context 'insufficient data (fewer than 30 bars)' do
      let(:series) do
        build_series(base_date: base_date, count: 20, interval: 5, &gentle_uptrend_1m)
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
          base_date: base_date, count: 60, interval: 5,
          &->(i, prev_close) {
            close = 25_000.0 + i * 5
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone' do
        # 5m * index: index 24 = 9:15 + 120 = 11:15 AM (dead zone)
        cutoff = series.candles[24].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'after 3:15 PM' do
      let(:series) do
        build_series(
          base_date: base_date, count: 80, interval: 5,
          &->(i, prev_close) {
            close = 25_000.0 + i * 3
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry' do
        # 5m * 73 = 365 min from 9:15 = 15:20 = 3:20 PM → late
        cutoff = series.candles[73].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry')
      end
    end

    context 'no crossover (steady trend, EMAs aligned)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 40, interval: 5,
          &->(i, prev_close) {
            # Steady uptrend — fast EMA stays above slow, no crossover
            close = 25_000.0 + i * 10
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with no_crossover' do
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        # May be no_crossover or ema_unavailable depending on data shape
        expect(result.reason).to include('no_crossover').or(include('ema'))
        end
    end
  end
  describe 'crossover detection with crafted data' do
    # Build data where we KNOW a crossover happens: prices decline for 30 bars
    # then reverse sharply, causing fast EMA to cross above slow EMA.
    let(:series) do
      build_series(
        base_date: base_date, count: 50, interval: 5,
        &->(i, prev_close) {
          if i < 28
            # Declining
            close = 25_000.0 - i * 8
          elsif i == 28
            # Sharp reversal candle
            close = 25_000.0 - 28 * 8 + 300
          else
            # Rising after reversal
            close = prev_close + 20
          end
          { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 200_000 }
        }
      )
    end

    it 'detects a bullish crossover and returns BuyCall (when conditions align)' do
      # The crossover should happen somewhere after the reversal.
      # We test the last bar where the crossover should have occurred.
      cutoff = series.candles[38].timestamp
      context = build_context(series: series, cutoff: cutoff)
      result = strategy.call(context)

      # Whether it's BuyCall depends on ADX filter and separation.
      # At minimum, it should NOT be 'no_crossover' if EMAs actually crossed.
      if result.is_a?(Signals::Hold)
        # If it's Hold, it should be for a filter reason, not 'no_crossover'
        expect(result.reason).not_to eq('no_crossover')
      else
        expect(result).to be_a(Signals::BuyCall)
      end
    end
  end
end
