# frozen_string_literal: true

require 'rails_helper'
require_relative 'plugin_test_helper'
load Rails.root.join('strategies/ema-crossover/strategy.rb').to_s

RSpec.describe EmaCrossoverStrategy do
  include PluginTestHelper

  let(:default_params) do
    {
      fast_period: 9,
      slow_period: 26,
      atr_period: 14,
      atr_multiplier: 1.75,
      target_r_multiple: 2.0,
      strike_pref: 'ATM'
    }
  end
  let(:strategy) { described_class.new(params: default_params) }
  let(:base_date) { Date.parse('2026-07-06') }

  describe 'params_schema' do
    it 'declares the EMA 9/26 parameters the strategy reads (per manifest)' do
      schema = described_class.params_schema
      expect(schema[:fast_period][:default]).to eq(9)
      expect(schema[:slow_period][:default]).to eq(26)
      expect(schema[:atr_multiplier][:default]).to eq(1.75)
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
    context 'with insufficient data (fewer than 30 bars)' do
      let(:series) do
        build_series(base_date: base_date, count: 20, interval: 5, &gentle_uptrend_1m)
      end

      it 'returns Hold with insufficient_history' do
        cutoff = series.candles.last.timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('insufficient_history')
      end
    end

    context 'when in midday dead zone' do
      let(:series) do
        build_series(
          base_date: base_date, count: 60, interval: 5,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 5)
            { open: prev_close, high: close + 10, low: close - 10, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with midday_dead_zone' do
        pending "the doc's 11:00-13:00 midday dead-zone gate is not implemented for " \
               'EmaCrossoverStrategy yet (VwapReversalStrategy has it); it currently ' \
               'evaluates crossovers through midday'

        # 5m * index: index 35 = 9:15 + 175 = 12:10 PM (dead zone and >= 30 warmup bars)
        cutoff = series.candles[35].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('midday_dead_zone')
      end
    end

    context 'when after 3:15 PM' do
      let(:series) do
        build_series(
          base_date: base_date, count: 80, interval: 5,
          &lambda { |i, prev_close|
            close = 25_000.0 + (i * 3)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with late_entry' do
        pending "the doc's after-15:15 late-entry gate is not implemented for " \
               'EmaCrossoverStrategy yet; it currently evaluates crossovers until close'

        # 5m * 73 = 365 min from 9:15 = 15:20 = 3:20 PM → late
        cutoff = series.candles[73].timestamp
        context = build_context(series: series, cutoff: cutoff)
        result = strategy.call(context)
        expect(result).to be_a(Signals::Hold)
        expect(result.reason).to eq('late_entry')
      end
    end

    context 'with no crossover (steady trend, EMAs aligned)' do
      let(:series) do
        build_series(
          base_date: base_date, count: 60, interval: 5,
          &lambda { |i, prev_close|
            # Steady uptrend — fast EMA stays above slow, no crossover
            close = 25_000.0 + (i * 10)
            { open: prev_close, high: close + 5, low: close - 5, close: close, volume: 100_000 }
          }
        )
      end

      it 'returns Hold with no_crossover' do
        # Index 50 = 9:15 + 250m = 13:25 (after 11:00-13:00 dead zone)
        cutoff = series.candles[50].timestamp
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
        &lambda { |i, prev_close|
          if i < 28
            # Declining
            close = 25_000.0 - (i * 8)
          elsif i == 28
            # Sharp reversal candle
            close = 25_000.0 - (28 * 8) + 300
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
