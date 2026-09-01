# frozen_string_literal: true

require 'rails_helper'

# NOTE: on the price patterns below: RubyTechnicalAnalysis::MovingAverages#ema (which
# CandleSeries#ema wraps, and this strategy calls directly) re-seeds its EMA from scratch on
# just the last `period` closes every call, rather than carrying a continuously-updated EMA
# forward from a much longer history. With a short synthetic series that makes EMA(26) react
# faster than textbook EMA(26) would, so a clean single crossover is easiest to construct as a
# sustained move in one direction followed by a sharp reversal — the fast/slow relationship
# actually flips at the START of the reversal leg, not partway through a single trend. The
# assertions below were derived empirically against the real indicator, not hand-calculated.
RSpec.describe 'EmaCrossoverStrategy', type: :strategy_plugin do
  before { load_strategy_plugin('ema-crossover') }

  let(:strategy) { EmaCrossoverStrategy.new(params: {}) }
  let(:tz) { '+05:30' }

  def series_from(prices, count: prices.size)
    candles = prices.first(count).each_with_index.map do |close, i|
      t = Time.zone.parse("2026-08-24 09:15:00 #{tz}") + (i * 5).minutes
      build_plugin_candle(t, open: close - 1.0, high: close + 2.0, low: close - 4.0, close: close)
    end
    build_plugin_series(candles)
  end

  def bearish_cross_prices
    prices = []
    p = 24_000.0
    30.times do
      p -= 3.0
 prices << p
    end
    7.times do
      p += 25.0
 prices << p
    end
    prices
  end

  def bullish_cross_prices
    prices = []
    p = 24_000.0
    30.times do
      p += 3.0
 prices << p
    end
    7.times do
      p -= 25.0
 prices << p
    end
    prices
  end

  it 'buys PE on a bearish EMA 9/26 crossover, with an ATR-based underlying exit' do
    series = series_from(bearish_cross_prices, count: 31) # ends exactly at the crossover bar
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::BuyPut)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    expect(rules[:stop_index_level]).to be > close
    expect(rules[:target_index_level]).to be < close
    expect(rules[:giveback_enabled]).to be(false)
  end

  it 'buys CE on a bullish EMA 9/26 crossover' do
    series = series_from(bullish_cross_prices, count: 31)
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::BuyCall)
    rules = signal.metadata[:exit_rules]
    close = series.candles.last.close
    expect(rules[:stop_index_level]).to be < close
    expect(rules[:target_index_level]).to be > close
  end

  it 'holds once a crossover has already fired earlier today (one trade/day)' do
    series = series_from(bearish_cross_prices, count: 33) # crossover at bar 30, two quiet bars after
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('already_traded_today')
  end

  it 'holds with insufficient history' do
    series = series_from(bearish_cross_prices, count: 10)
    signal = strategy.call(build_plugin_context(series, cutoff: series.candles.last.timestamp))

    expect(signal).to be_a(Signals::Hold)
    expect(signal.reason).to eq('insufficient_history')
  end
end
